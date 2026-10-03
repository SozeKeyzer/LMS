/**
 * ScheduleGenerationService
 * Generates initial Payment_Schedule__c rows when Debt_Position Status → Active.
 *
 * Amortisation_Rules__c, Fee_Structures__c, Interest_Rate_Terms__c all have
 * Master-Detail to Debt_Position__c — queried directly via Debt_Position__c field.
 *
 * Reads from EXISTING Debt_Position__c fields:
 *   Payment_Frequency__c           — Monthly / Quarterly / Semi_Annual / Annual
 *   First_Payment_Date__c          — anchor date
 *   Payment_Date_of_the_Month__c   — day-of-month override
 *   Payment_Date_Rule__c           — Following / Modified_Following / Preceding
 *   Day_Count_Convention__c        — ACT_365 / ACT_360 etc
 *   Position_Maturity_Date__c      — schedule end date
 *   Position_Notional__c           — original principal
 */
public class ScheduleGenerationService {

    private static final Map<String,Integer> FREQ_MONTHS = new Map<String,Integer>{
        'Monthly'     => 1,
        'Quarterly'   => 3,
        'Semi_Annual' => 6,
        'Annual'      => 12
    };

    // Wrapper kept for trigger/automation callers — does not force-regenerate
    public static List<Payment_Schedule__c> generate(Id dpId) {
        return generate(dpId, false);
    }

    // Preview-only: computes rows in-memory with no DML at all.
    // Returns correct Principal_Due__c, Period_Start__c, Due_Date__c etc.
    // Formula fields (Total_Due__c) are null — compute on client side.
    public static List<Payment_Schedule__c> previewRows(Id dpId) {
        return generate(dpId, true, true);
    }

    /**
     * forceRegen=false (default): blocks if any Projected rows already exist.
     * forceRegen=true (manual recalc): skips the Projected-row guard; upserts
     *   new values over existing rows. Due/Paid rows are never overwritten.
     *   Returns the successfully generated rows with their persisted Ids.
     */
    public static List<Payment_Schedule__c> generate(Id dpId, Boolean forceRegen) {
        return generate(dpId, forceRegen, false);
    }

    private static List<Payment_Schedule__c> generate(Id dpId, Boolean forceRegen, Boolean previewOnly) {
        Debt_Position__c dp = [
            SELECT Id, Name,
                   Financial_Instrument__c,
                   Position_Notional__c,
                   Outstanding_Balance__c,
                   Waterfall_Rule__c,
                   Day_Count_Convention__c,
                   Payment_Frequency__c,
                   Payment_Date_Rule__c,
                   Payment_Date_of_the_Month__c,
                   First_Payment_Date__c,
                   Accrual_Start_Date__c,
                   Position_Maturity_Date__c,
                   Loan_Component_Type__c
            FROM Debt_Position__c
            WHERE Id = :dpId
        ];

        // Guards — required field checks always apply
        if (dp.First_Payment_Date__c == null) {
            if (previewOnly) return new List<Payment_Schedule__c>();
            return logAndFlush(dpId, 'Schedule generation skipped — First_Payment_Date__c is not set.');
        }
        if (dp.Position_Maturity_Date__c == null) {
            if (previewOnly) return new List<Payment_Schedule__c>();
            return logAndFlush(dpId, 'Schedule generation skipped — Position_Maturity_Date__c is not set.');
        }
        if (String.isBlank(dp.Payment_Frequency__c)) {
            if (previewOnly) return new List<Payment_Schedule__c>();
            return logAndFlush(dpId, 'Schedule generation skipped — Payment_Frequency__c is not set.');
        }

        // Idempotency — only block on existing Projected rows.
        // Due/Paid rows represent historical payments and must not prevent
        // regeneration of the remaining future schedule.
        if (!forceRegen && !previewOnly) {
            Integer existingProjected = [
                SELECT COUNT() FROM Payment_Schedule__c
                WHERE Debt_Position__c = :dpId
                  AND Status__c = 'Projected'
            ];
            if (existingProjected > 0) {
                return logAndFlush(dpId, 'Schedule generation skipped — '
                    + existingProjected + ' Projected rows already exist.');
            }
        }

        String dayCountConvention = String.isNotBlank(dp.Day_Count_Convention__c)
            ? dp.Day_Count_Convention__c : 'ACT_365';
        Integer freqMonths = FREQ_MONTHS.get(dp.Payment_Frequency__c);
        if (freqMonths == null) freqMonths = 3;
        Decimal originalPrincipal = dp.Position_Notional__c != null
            ? dp.Position_Notional__c
            : (dp.Outstanding_Balance__c != null ? dp.Outstanding_Balance__c : 0);

        // Determine Pricing_Basis for rate finalisation (Rule R17)
        // Reads IRT.Pricing_Basis__c — Fixed = Not_Applicable, Floating = Projected_Rate
        String pricingBasis = 'Fixed';
        Decimal placeholderBaseRate = null;
        Decimal placeholderSpread = null;
        Decimal placeholderAllInRate = null;

        List<Interest_Rate_Terms__c> irtCheck = [
            SELECT Id, Pricing_Basis__c, Applicable_Fixed_Rate__c, Spread__c,
                   Base_Rate_Value__c, Floor_Rate__c, Ceiling_Rate__c
            FROM Interest_Rate_Terms__c
            WHERE Debt_Position__c = :dpId
            AND Application_Status__c IN ('Pending','Applied')
            ORDER BY Contractual_Effective_From__c ASC LIMIT 1
        ];
        if (!irtCheck.isEmpty()) {
            pricingBasis = irtCheck[0].Pricing_Basis__c != null ? irtCheck[0].Pricing_Basis__c : 'Fixed';
            if (pricingBasis == 'Floating') {
                // Use first known rate as placeholder per spec v5 Part 2.8.2
                placeholderBaseRate = irtCheck[0].Base_Rate_Value__c;
                placeholderSpread   = irtCheck[0].Spread__c;
                if (placeholderBaseRate != null && placeholderSpread != null) {
                    Decimal raw = placeholderBaseRate + placeholderSpread;
                    if (irtCheck[0].Floor_Rate__c != null && raw < irtCheck[0].Floor_Rate__c) raw = irtCheck[0].Floor_Rate__c;
                    if (irtCheck[0].Ceiling_Rate__c != null && raw > irtCheck[0].Ceiling_Rate__c) raw = irtCheck[0].Ceiling_Rate__c;
                    placeholderAllInRate = raw;
                }
            }
        }

        // Annual rate used for Equal_Instalment amortisation formula
        Decimal effectiveAnnualRate = null;
        if (!irtCheck.isEmpty()) {
            effectiveAnnualRate = (pricingBasis == 'Fixed')
                ? irtCheck[0].Applicable_Fixed_Rate__c
                : placeholderAllInRate;
        }

        // ── Load related objects via Debt_Position__c (Master-Detail) ─────────
        // Amortisation_Rules — child of DP
        String amortMethod = 'Bullet';
        Id amortRuleId = null;
        List<Amortisation_Rules__c> amortRules = [
            SELECT Id, Amortisation_Method__c
            FROM Amortisation_Rules__c
            WHERE Debt_Position__c = :dpId
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        if (!amortRules.isEmpty()) {
            amortRuleId = amortRules[0].Id;
            if (amortRules[0].Amortisation_Method__c != null) {
                amortMethod = amortRules[0].Amortisation_Method__c;
            }
        }

        // Fee_Structures — child of DP
        List<Fee_Structures__c> feeStructures = [
            SELECT Id, Rate__c, Amount__c
            FROM Fee_Structures__c
            WHERE Debt_Position__c = :dpId
            LIMIT 50
        ];
        Decimal periodFees = computePeriodFees(feeStructures, originalPrincipal, freqMonths);

        // Interest_Rate_Terms — child of DP
        Id irtId = null;
        List<Interest_Rate_Terms__c> irTerms = [
            SELECT Id, Application_Status__c
            FROM Interest_Rate_Terms__c
            WHERE Debt_Position__c = :dpId
            AND Application_Status__c IN ('Pending','Applied')
            ORDER BY Contractual_Effective_From__c ASC
            LIMIT 1
        ];
        if (!irTerms.isEmpty()) irtId = irTerms[0].Id;

        // ── Build period grid ─────────────────────────────────────────────────
        // Spec Part 5.3: period anchor is Accrual_Start_Date__c, not First_Payment_Date - freq.
        // If Accrual_Start_Date is null (older DPs), fall back to First_Payment_Date - freqMonths
        // so that existing schedules regenerate with the same External_Ids.
        Date accrualStartDate = dp.Accrual_Start_Date__c != null
            ? dp.Accrual_Start_Date__c
            : dp.First_Payment_Date__c.addMonths(-freqMonths);
        List<PeriodRow> periods = buildPeriodGrid(
            accrualStartDate, dp.First_Payment_Date__c, dp.Position_Maturity_Date__c,
            freqMonths, dp.Payment_Date_of_the_Month__c, dp.Payment_Date_Rule__c
        );

        Map<Integer,Decimal> principalByPeriod = computePrincipal(
            amortMethod, originalPrincipal, periods.size(), effectiveAnnualRate, freqMonths);
        String corrId = TriggerContext.getInstance().correlationId;
        List<Payment_Schedule__c> rows = new List<Payment_Schedule__c>();

        for (Integer i = 0; i < periods.size(); i++) {
            PeriodRow pr = periods[i];
            rows.add(new Payment_Schedule__c(
                Debt_Position__c                = dpId,
                Period_Start__c                 = pr.periodStart,
                Period_End__c                   = pr.periodEnd,
                Due_Date__c                     = pr.dueDate,
                Principal_Due__c                = principalByPeriod.containsKey(i) ? principalByPeriod.get(i) : 0,
                Interest_Due__c                 = 0,  // Rule R1: PeriodCloseBatch fills from Accrual_Daily roll-up
                Fees_Due__c                     = periodFees,
                Status__c                       = 'Projected',
                Is_Immutable__c                 = false,
                Day_Count_Convention_Used__c    = dayCountConvention,
                Principal_Basis_Used__c         = originalPrincipal,
                Amortisation_Segment_Used__c    = amortRuleId != null ? String.valueOf(amortRuleId) : null,
                Interest_Rate_Terms_Used__c     = irtId != null ? String.valueOf(irtId) : null,
                Engine_Version_Snapshot__c      = CalculationEngineBase.ENGINE_VERSION,
                Calculation_Timestamp__c        = DateTime.now(),
                Correlation_Id__c               = corrId,
                Source__c                       = 'System_Calculated',
                Engine_Version__c               = CalculationEngineBase.ENGINE_VERSION,
                External_Id__c                  = String.valueOf(dpId) + '-' + pr.periodStart.format(),
                // Rule R17: Rate finalisation status per spec v5
                Rate_Finalisation_Status__c     = pricingBasis == 'Floating' ? 'Projected_Rate' : 'Not_Applicable',
                // Placeholder rate fields for floating loans
                Placeholder_Base_Rate__c        = pricingBasis == 'Floating' ? placeholderBaseRate : null,
                Placeholder_Spread__c           = pricingBasis == 'Floating' ? placeholderSpread : null,
                Placeholder_All_In_Rate__c      = pricingBasis == 'Floating' ? placeholderAllInRate : null
            ));
        }

        // Preview mode: return computed rows without any DML
        if (previewOnly) {
            return rows;
        }

        // Protect rows that have already been settled (Due, Paid, Overdue, etc.)
        // from being overwritten by the upsert. Only Projected/Superseded/Cancelled
        // rows may be updated in-place.
        Set<String> protectedExtIds = new Set<String>();
        for (Payment_Schedule__c ps : [
            SELECT External_Id__c FROM Payment_Schedule__c
            WHERE Debt_Position__c = :dpId
              AND Status__c NOT IN ('Projected', 'Superseded', 'Cancelled')
              AND External_Id__c != null
        ]) {
            protectedExtIds.add(ps.External_Id__c);
        }
        List<Payment_Schedule__c> toUpsert = new List<Payment_Schedule__c>();
        for (Payment_Schedule__c row : rows) {
            if (!protectedExtIds.contains(row.External_Id__c)) {
                toUpsert.add(row);
            }
        }

        Schema.SObjectField extId = Payment_Schedule__c.Fields.External_Id__c;
        Database.UpsertResult[] results = Database.upsert(toUpsert, extId, false);

        Integer successCount = 0;
        List<Payment_Schedule__c> generated = new List<Payment_Schedule__c>();
        List<String> errs = new List<String>();
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                successCount++;
                toUpsert[i].Id = results[i].getId();
                generated.add(toUpsert[i]);
            } else {
                for (Database.Error e : results[i].getErrors()) errs.add(e.getMessage());
            }
        }

        AuditEventLogger.logEngine('SCHEDULE_GENERATED','Debt_Position__c', String.valueOf(dpId),
            'Schedule generated. Periods: ' + successCount
            + ' | Frequency: ' + dp.Payment_Frequency__c
            + ' | DayCount: ' + dayCountConvention
            + ' | Principal: ' + originalPrincipal
            + ' | AmortMethod: ' + amortMethod
            + (protectedExtIds.isEmpty() ? '' : ' | Protected (Due/Paid): ' + protectedExtIds.size())
            + (errs.isEmpty() ? '' : ' | ERRORS: ' + String.join(errs,'; ')));
        AuditEventLogger.flush();

        return generated;
    }

    private static List<Payment_Schedule__c> logAndFlush(Id dpId, String msg) {
        AuditEventLogger.logEngine('SCHEDULE_GENERATED','Debt_Position__c', String.valueOf(dpId), msg);
        AuditEventLogger.flush();
        return new List<Payment_Schedule__c>();
    }

    // BREAKING CHANGE NOTE (spec Part 5.3):
    // Period_End__c is now period_start + freq - 1 day (last day of accrual).
    // Due_Date__c advances separately and is one day after Period_End for standard periods.
    // Re-running generate() on existing Debt Positions after this deploy will shift Period_End__c
    // by -1 day on all Projected rows via the External_Id upsert. This is correct per spec
    // but changes existing org data — coordinate data migration with the release.
    @TestVisible
    static List<PeriodRow> buildPeriodGrid(
        Date accrualStartDate, Date firstPaymentDate, Date maturityDate,
        Integer freqMonths, Decimal dayOfMonth, String dateRule
    ) {
        List<PeriodRow> grid = new List<PeriodRow>();
        Date periodStart = accrualStartDate;
        Date nextDueDate = firstPaymentDate; // due date advances independently of period end

        // Spec Part 6.2: loop uses <= so the maturity day is covered as a final stub if needed.
        // Cap uses > (not >=) so a period ending exactly on maturity is NOT forced into a stub.
        while (periodStart <= maturityDate) {
            Date rawPeriodEnd    = periodStart.addMonths(freqMonths).addDays(-1);
            Boolean isFinalStub  = (rawPeriodEnd > maturityDate);
            Date periodEnd       = isFinalStub ? maturityDate : rawPeriodEnd;

            // Final stub: apply rule anchored to periodEnd (= maturity), then cap result
            // at maturityDate so rules like "X Days After Period End" can't overshoot.
            Date dueDate;
            if (isFinalStub) {
                Date ruleBased = applyDateRule(periodEnd, periodEnd, dayOfMonth, dateRule);
                dueDate = ruleBased <= maturityDate ? ruleBased : maturityDate;
            } else if (grid.isEmpty()) {
                // Spec Part 5.2A: first row due date = First_Payment_Date directly, no rule applied
                dueDate = firstPaymentDate;
            } else {
                dueDate = applyDateRule(nextDueDate, periodEnd, dayOfMonth, dateRule);
            }
            grid.add(new PeriodRow(periodStart, periodEnd, dueDate));

            periodStart  = periodEnd.addDays(1);
            nextDueDate  = nextDueDate.addMonths(freqMonths);
        }
        return grid;
    }

    private static Date applyDateRule(Date rawDate, Date periodEnd, Decimal dayOfMonth, String dateRule) {
        // X Days After Period End — ignores rawDate entirely; Payment_Date_of_the_Month__c = number of days
        if (dateRule == 'X Days After Period End') {
            Integer xDays = dayOfMonth != null && dayOfMonth > 0 ? dayOfMonth.intValue() : 0;
            return periodEnd.addDays(xDays);
        }
        // Month-anchored rules: derive from periodEnd's month so the due date
        // lands within the period, not in the following period's month.
        if (dateRule == 'First Day of Month') {
            return Date.newInstance(periodEnd.year(), periodEnd.month(), 1);
        }
        if (dateRule == 'Last Day of Month') {
            return Date.newInstance(periodEnd.year(), periodEnd.month(), Date.daysInMonth(periodEnd.year(), periodEnd.month()));
        }
        if (dateRule == 'Specific Day of Month') {
            Integer dom = dayOfMonth != null && dayOfMonth > 0 ? dayOfMonth.intValue() : 1;
            return Date.newInstance(periodEnd.year(), periodEnd.month(), Math.min(dom, Date.daysInMonth(periodEnd.year(), periodEnd.month())));
        }
        // Business day rules: apply dayOfMonth pin on rawDate first (if set), then adjust
        Date adjusted = rawDate;
        if (dayOfMonth != null && dayOfMonth > 0) {
            Integer dom = dayOfMonth.intValue();
            adjusted = Date.newInstance(rawDate.year(), rawDate.month(), Math.min(dom, Date.daysInMonth(rawDate.year(), rawDate.month())));
        }
        if (dateRule == 'Preceding Business Day')         return adjustToPrecedingBusinessDay(adjusted);
        if (dateRule == 'Modified Following Business Day') return adjustToBusinessDay(adjusted, 'Modified_Following');
        if (dateRule == 'Other') return adjusted;
        // 'Following Business Day' and blank both roll forward
        return adjustToBusinessDay(adjusted, 'Following');
    }

    private static Date adjustToPrecedingBusinessDay(Date d) {
        Integer dow = Math.mod(Date.newInstance(1900,1,7).daysBetween(d), 7);
        if (dow == 6) return d.addDays(-1); // Saturday → Friday
        if (dow == 0) return d.addDays(-2); // Sunday → Friday
        return d;
    }

    private static Date adjustToBusinessDay(Date d, String rule) {
        Date check = d;
        Integer dow = Math.mod(Date.newInstance(1900,1,7).daysBetween(check), 7);
        if (dow == 6) check = check.addDays(2); // Saturday → Monday
        if (dow == 0) check = check.addDays(1);
        if (rule == 'Modified_Following' && check.month() != d.month()) {
            check = d.addDays(-1);
            dow = Math.mod(Date.newInstance(1900,1,7).daysBetween(check), 7);
            if (dow == 6) check = check.addDays(-1);
            if (dow == 0) check = check.addDays(-2); // Sunday → Friday
        }
        return check;
    }

    private static Map<Integer,Decimal> computePrincipal(
        String method, Decimal principal, Integer periods,
        Decimal annualRate, Integer freqMonths
    ) {
        Map<Integer,Decimal> result = new Map<Integer,Decimal>();
        if (periods == 0) return result;

        // Normalise: picklist stores "Equal Principal" (space); code historically used underscore
        String normMethod = method != null ? method.replace(' ', '_') : 'Bullet';

        if (normMethod == 'Equal_Principal') {
            // Divide evenly; last period absorbs cumulative rounding difference
            Decimal perPeriod = (principal / periods).setScale(2, RoundingMode.HALF_EVEN);
            Decimal cumulative = 0;
            for (Integer i = 0; i < periods - 1; i++) {
                result.put(i, perPeriod);
                cumulative += perPeriod;
            }
            result.put(periods - 1, (principal - cumulative).setScale(2, RoundingMode.HALF_EVEN));

        } else if (normMethod == 'Equal_Instalment') {
            // Annuity schedule: constant total payment; split into interest + principal each period.
            // periodsPerYear derived from freqMonths so quarterly/semi/annual are handled correctly.
            if (annualRate == null || annualRate == 0 || freqMonths == null) {
                // Zero or unknown rate: treat as equal principal
                Decimal perPeriod = (principal / periods).setScale(2, RoundingMode.HALF_EVEN);
                Decimal cumulative = 0;
                for (Integer i = 0; i < periods - 1; i++) { result.put(i, perPeriod); cumulative += perPeriod; }
                result.put(periods - 1, (principal - cumulative).setScale(2, RoundingMode.HALF_EVEN));
            } else {
                Integer periodsPerYear = 12 / freqMonths;
                Decimal periodicRate = (annualRate / 100) / periodsPerYear;
                Decimal factor = (Decimal) Math.pow((Double)(1 + periodicRate), periods);
                Decimal instalment = (principal * periodicRate * factor / (factor - 1))
                    .setScale(2, RoundingMode.HALF_EVEN);
                Decimal balance = principal;
                for (Integer i = 0; i < periods; i++) {
                    Decimal interest = (balance * periodicRate).setScale(2, RoundingMode.HALF_EVEN);
                    Decimal principalCmpt = i == periods - 1
                        ? balance  // last period: absorb residual
                        : (instalment - interest).setScale(2, RoundingMode.HALF_EVEN);
                    result.put(i, principalCmpt);
                    balance = (balance - principalCmpt).setScale(6, RoundingMode.HALF_EVEN);
                }
            }

        } else {
            // Bullet (default): all principal in final period
            for (Integer i = 0; i < periods - 1; i++) result.put(i, 0);
            result.put(periods - 1, principal);
        }
        return result;
    }

    private static Decimal computePeriodFees(List<Fee_Structures__c> feeList, Decimal principal, Integer freqMonths) {
        Decimal totalAnnualFee = 0;
        for (Fee_Structures__c fs : feeList) {
            try {
                Object rate = fs.get('Rate__c');
                if (rate != null && (Decimal)rate > 0) totalAnnualFee += principal * ((Decimal)rate / 100);
            } catch (Exception e) {}
            try {
                Object amt = fs.get('Amount__c');
                if (amt != null && (Decimal)amt > 0) totalAnnualFee += (Decimal)amt;
            } catch (Exception e) {}
        }
        return (totalAnnualFee / (12.0 / freqMonths)).setScale(2, RoundingMode.HALF_EVEN);
    }

    public class PeriodRow {
        public Date periodStart { get; private set; }
        public Date periodEnd   { get; private set; }
        public Date dueDate     { get; private set; }
        public PeriodRow(Date s, Date e, Date d) { periodStart=s; periodEnd=e; dueDate=d; }
    }
}