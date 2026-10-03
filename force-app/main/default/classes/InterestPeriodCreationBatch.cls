/**
 * InterestPeriodCreationBatch — runs T-2 BD before each period start (spec §5.5.4).
 *
 * FLOATING-RATE DPs:
 *   Creates Interest_Period with Status = Pending, null rate fields.
 *   Sets Index_Type (e.g. BBSW_3M) and Fixing_Date = today (the T-2 date).
 *   Rate is locked later by RateFixingIngestionService → PaymentScheduleRateFinaliser
 *   when the actual fixing is published.
 *
 * FIXED-RATE DPs:
 *   Creates Interest_Period with Status = Active, All_In_Rate set immediately from IRT.
 *   No fixing event — nothing to wait for.
 *
 * Idempotent: DPs that already have any Interest_Period for targetStart are skipped.
 * Batch size 50 — createPendingPeriod / createActivePeriod each do 1 SOQL + 1 DML per DP.
 */
public class InterestPeriodCreationBatch implements Database.Batchable<SObject>, Database.Stateful {

    private Date    targetStart;
    private Integer processed = 0;
    private Integer skipped   = 0;
    private Integer errors    = 0;

    public InterestPeriodCreationBatch(Date start) { this.targetStart = start; }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Outstanding_Balance__c
            FROM Debt_Position__c
            WHERE Status__c = 'Active'
        ]);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        TriggerContext.getInstance().refreshCorrelationId();
        String correlationId = TriggerContext.getInstance().correlationId;
        Date   fixingDate    = Date.today(); // T-2 date = today when the batch runs

        Set<Id> dpIds = new Map<Id, SObject>(scope).keySet();
        System.debug('DpIds in current batch scope: ' + dpIds);

        // 1. Best applicable IRT per DP — Applied beats Pending; latest effective date wins.
        //    Must cover targetStart within its contractual window.
        Map<Id, Interest_Rate_Terms__c> dpToIRT = new Map<Id, Interest_Rate_Terms__c>();
        for (Interest_Rate_Terms__c irt : [
            SELECT Id, Debt_Position__c,
                   Pricing_Basis__c, Index_Type__c,
                   Applicable_Fixed_Rate__c, Spread__c,
                   Floor_Rate__c, Ceiling_Rate__c,
                   Application_Status__c,
                   Contractual_Effective_From__c, Contractual_Effective_To__c
            FROM Interest_Rate_Terms__c
            WHERE Debt_Position__c IN :dpIds
            AND Application_Status__c IN ('Applied', 'Pending')
            AND Contractual_Effective_From__c <= :targetStart
            AND (Contractual_Effective_To__c >= :targetStart OR Contractual_Effective_To__c = null)
            ORDER BY Contractual_Effective_From__c DESC
        ]) {
            if (!dpToIRT.containsKey(irt.Debt_Position__c)) {
                dpToIRT.put(irt.Debt_Position__c, irt);
            } else if (irt.Application_Status__c == 'Applied'
                       && dpToIRT.get(irt.Debt_Position__c).Application_Status__c != 'Applied') {
                // Applied always preferred over Pending for the same DP
                dpToIRT.put(irt.Debt_Position__c, irt);
            }
        }

        System.debug('DP to IRT map: ' + dpToIRT);

        // 2. Payment_Schedule row that defines the period boundaries.
        //    ScheduleGenerationService creates these at DP activation — period start/end
        //    are the canonical source of truth for what period the batch should create.
        Map<Id, Payment_Schedule__c> dpToSchedule = new Map<Id, Payment_Schedule__c>();
        for (Payment_Schedule__c ps : [
            SELECT Id, Debt_Position__c, Period_End__c
            FROM Payment_Schedule__c
            WHERE Debt_Position__c IN :dpIds
            AND Period_Start__c = :targetStart
            AND Status__c NOT IN ('Superseded', 'Cancelled')
            ORDER BY CreatedDate ASC
        ]) {
            if (!dpToSchedule.containsKey(ps.Debt_Position__c)) {
                dpToSchedule.put(ps.Debt_Position__c, ps);
            }
        }

        System.debug('DP to Payment Schedule map: ' + dpToSchedule);

        // 3. Idempotency — skip DPs that already have an Interest_Period for targetStart
        //    (covers both normal re-run and the defensive create-and-lock path in RateFixingIngestionService).
        Set<Id> alreadyHasPeriod = new Set<Id>();
        for (Interest_Period__c ip : [
            SELECT Debt_Position__c
            FROM Interest_Period__c
            WHERE Debt_Position__c IN :dpIds
            AND Period_Start__c = :targetStart
        ]) {
            alreadyHasPeriod.add(ip.Debt_Position__c);
        }

        // --- Process each Debt Position ---
        for (SObject sobj : scope) {
            Debt_Position__c dp = (Debt_Position__c) sobj;

            if (alreadyHasPeriod.contains(dp.Id)) {
                skipped++;
                continue;
            }

            Interest_Rate_Terms__c irt = dpToIRT.get(dp.Id);
            if (irt == null) {
                AuditEventLogger.logEngine('PERIOD_SKIPPED', 'Debt_Position__c',
                    String.valueOf(dp.Id),
                    'No applicable IRT (Applied/Pending) covering period start: ' + targetStart);
                skipped++;
                continue;
            }

            Payment_Schedule__c ps = dpToSchedule.get(dp.Id);
            if (ps == null) {
                AuditEventLogger.logEngine('PERIOD_SKIPPED', 'Debt_Position__c',
                    String.valueOf(dp.Id),
                    'No Payment_Schedule row found for period start: ' + targetStart
                    + '. Ensure ScheduleGenerationService ran at DP activation.');
                skipped++;
                continue;
            }

            String  basis  = String.isBlank(irt.Pricing_Basis__c) ? 'Fixed' : irt.Pricing_Basis__c;
            Decimal margin = irt.Spread__c != null ? irt.Spread__c : 0;

            try {
                Interest_Period__c created;

                if (basis == 'Floating') {
                    // Pending — rate fields null, locked by RateFixingIngestionService
                    created = InterestPeriodService.createPendingPeriod(
                        dp.Id, irt.Id, targetStart, ps.Period_End__c,
                        irt.Index_Type__c, fixingDate, margin, correlationId
                    );
                    AuditEventLogger.logEngine('PERIOD_CREATED', 'Interest_Period__c',
                        String.valueOf(created.Id),
                        'Floating period created (Pending). DP: ' + dp.Id
                        + ' | Start: ' + targetStart + ' | End: ' + ps.Period_End__c
                        + ' | IndexType: ' + irt.Index_Type__c
                        + ' | FixingDate: ' + fixingDate
                        + ' | Margin: ' + margin + '%');

                } else {
                    // Fixed — Active immediately, all rate fields set
                    Decimal contractualRate = irt.Applicable_Fixed_Rate__c != null
                        ? irt.Applicable_Fixed_Rate__c : 0;
                    created = InterestPeriodService.createActivePeriod(
                        dp.Id, irt.Id, targetStart, ps.Period_End__c,
                        contractualRate, irt.Floor_Rate__c, irt.Ceiling_Rate__c, correlationId
                    );
                    AuditEventLogger.logEngine('PERIOD_CREATED', 'Interest_Period__c',
                        String.valueOf(created.Id),
                        'Fixed period created (Active). DP: ' + dp.Id
                        + ' | Start: ' + targetStart + ' | End: ' + ps.Period_End__c
                        + ' | Rate: ' + contractualRate + '%'
                        + ' | AllIn: ' + created.All_In_Rate__c + '%');
                }

                processed++;

            } catch (InterestPeriodService.InterestPeriodException ex) {
                // VR.IP.05 overlap — not a system error, log and skip
                AuditEventLogger.logEngine('PERIOD_SKIPPED', 'Debt_Position__c',
                    String.valueOf(dp.Id),
                    'Period creation blocked (overlap rule VR.IP.05): ' + ex.getMessage());
                skipped++;

            } catch (Exception ex) {
                AuditEventLogger.logEngine('PERIOD_ERROR', 'Debt_Position__c',
                    String.valueOf(dp.Id),
                    'Unexpected error creating period: ' + ex.getMessage());
                errors++;
            }
        }

        AuditEventLogger.flush();
    }

    public void finish(Database.BatchableContext bc) {
        AuditEventLogger.logEngine('PERIOD_CREATION_COMPLETE', 'InterestPeriodCreationBatch', null,
            'Batch complete.'
            + ' TargetStart: ' + targetStart
            + ' | Processed: ' + processed
            + ' | Skipped: '   + skipped
            + ' | Errors: '    + errors);
        AuditEventLogger.flush();
    }
}