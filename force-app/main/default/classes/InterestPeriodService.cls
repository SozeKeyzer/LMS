/**
 * InterestPeriodService
 * Creates and manages Interest_Period__c records.
 *
 * Lifecycle per spec §5.2.5:
 *   FLOATING  → createPendingPeriod (Pending, null rates)
 *             → lockPeriod (Active) when Rate_Index_Fixing arrives
 *   FIXED     → createActivePeriod (Active, rate set immediately — no fixing event)
 *
 * VR.IP.05: no overlapping Active period per Debt Position. Checked on every creation.
 */
public class InterestPeriodService {

    // ── Creation ─────────────────────────────────────────────────────────────────

    /**
     * FLOATING-RATE path.
     * Creates a Pending Interest_Period. Rate fields are intentionally null —
     * they are populated by lockPeriod() when the Rate_Index_Fixing arrives.
     */
    public static Interest_Period__c createPendingPeriod(
        Id      dpId,
        Id      appliedRateTermsId,
        Date    periodStart,
        Date    periodEnd,
        String  indexType,
        Date    fixingDate,
        Decimal margin,
        String  correlationId
    ) {
        assertNoActivePeriodOverlap(dpId, periodStart, periodEnd);

        Interest_Period__c ip = new Interest_Period__c(
            Debt_Position__c      = dpId,
            Applied_Rate_Terms__c = appliedRateTermsId,
            Period_Start__c       = periodStart,
            Period_End__c         = periodEnd,
            Index_Type__c        = indexType,
            Fixing_Date__c        = fixingDate,
            Margin_Used__c        = margin,
            Fixed_Index_Rate__c   = null,
            All_In_Rate__c        = 0,    //was null initially had to make 0 as field is required.
            Calculated_Rate__c    = null,
            Status__c             = 'Pending',
            Correlation_Id__c     = correlationId,
            Source__c             = 'System_Calculated',
            Engine_Version__c     = CalculationEngineBase.ENGINE_VERSION,
            External_Id__c        = String.valueOf(dpId) + '-' + periodStart.format()
        );

        TriggerContext.getInstance().bypassGuards = true;
        insert ip;
        TriggerContext.getInstance().bypassGuards = false;
        return ip;
    }

    /**
     * FIXED-RATE path.
     * Creates an Active Interest_Period with all rate fields populated immediately.
     * Index_Type and Fixing_Date are null — fixed loans have no benchmark or fixing event.
     * Status goes directly to Active (nothing to wait for).
     */
    public static Interest_Period__c createActivePeriod(
        Id      dpId,
        Id      appliedRateTermsId,
        Date    periodStart,
        Date    periodEnd,
        Decimal contractualRate,
        Decimal floor,
        Decimal ceiling,
        String  correlationId
    ) {
        assertNoActivePeriodOverlap(dpId, periodStart, periodEnd);

        Decimal allIn = contractualRate != null ? contractualRate : 0;
        if (floor    != null && allIn < floor)    allIn = floor;
        if (ceiling  != null && allIn > ceiling)  allIn = ceiling;

        Interest_Period__c ip = new Interest_Period__c(
            Debt_Position__c      = dpId,
            Applied_Rate_Terms__c = appliedRateTermsId,
            Period_Start__c       = periodStart,
            Period_End__c         = periodEnd,
            Index_Type__c        = null,
            Fixing_Date__c        = null,
            Fixed_Index_Rate__c   = null,
            Margin_Used__c        = contractualRate,
            All_In_Rate__c        = allIn,
            Calculated_Rate__c    = allIn,
            Status__c             = 'Active',
            Correlation_Id__c     = correlationId,
            Source__c             = 'System_Calculated',
            Engine_Version__c     = CalculationEngineBase.ENGINE_VERSION,
            External_Id__c        = String.valueOf(dpId) + '-' + periodStart.format()
        );

        TriggerContext.getInstance().bypassGuards = true;
        insert ip;
        TriggerContext.getInstance().bypassGuards = false;
        return ip;
    }

    // ── Rate lock (floating lifecycle step 2) ────────────────────────────────────

    /**
     * Locks a Pending Interest_Period when its Rate_Index_Fixing arrives.
     * Computes All_In_Rate = fixedIndexRate + Margin_Used, clamped by floor/ceiling from IRT.
     * Transitions Status: Pending → Active.
     * No-op if the period is already Active or Closed.
     */
    public static void lockPeriod(Id periodId, Decimal fixedIndexRate) {
        Interest_Period__c ip = [
            SELECT Id, Status__c, Margin_Used__c, Applied_Rate_Terms__c
            FROM Interest_Period__c WHERE Id = :periodId
        ];

        if (ip.Status__c != 'Pending') return;

        Decimal margin = ip.Margin_Used__c != null ? ip.Margin_Used__c : 0;
        Decimal allIn  = (fixedIndexRate != null ? fixedIndexRate : 0) + margin;

        // Apply floor/ceiling from IRT if available
        if (ip.Applied_Rate_Terms__c != null) {
            Interest_Rate_Terms__c irt = [
                SELECT Floor_Rate__c, Ceiling_Rate__c
                FROM Interest_Rate_Terms__c WHERE Id = :ip.Applied_Rate_Terms__c
            ];
            if (irt.Floor_Rate__c   != null && allIn < irt.Floor_Rate__c)   allIn = irt.Floor_Rate__c;
            if (irt.Ceiling_Rate__c != null && allIn > irt.Ceiling_Rate__c) allIn = irt.Ceiling_Rate__c;
        }

        TriggerContext.getInstance().bypassGuards = true;
        update new Interest_Period__c(
            Id                  = periodId,
            Fixed_Index_Rate__c = fixedIndexRate,
            All_In_Rate__c      = allIn,
            Calculated_Rate__c  = allIn,
            Status__c           = 'Active'
        );
        TriggerContext.getInstance().bypassGuards = false;

        AuditEventLogger.logEngine('PERIOD_LOCKED', 'Interest_Period__c', String.valueOf(periodId),
            'Rate fixing locked. Index: ' + fixedIndexRate + '% | Margin: ' + margin + '% | All-in: ' + allIn + '%.');
        AuditEventLogger.flush();
    }

    // ── Period close ─────────────────────────────────────────────────────────────

    public static void closePeriod(Id periodId) {
        TriggerContext.getInstance().bypassGuards = true;
        update new Interest_Period__c(Id = periodId, Status__c = 'Closed');
        List<Accrual_Daily__c> rows = [
            SELECT Id FROM Accrual_Daily__c WHERE Interest_Period__c = :periodId AND Is_Immutable__c = false
        ];
        for (Accrual_Daily__c ad : rows) ad.Is_Immutable__c = true;
        if (!rows.isEmpty()) update rows;
        TriggerContext.getInstance().bypassGuards = false;
        AuditEventLogger.logEngine('PERIOD_CLOSED', 'Interest_Period__c', String.valueOf(periodId),
            'Period closed and accruals crystallised.');
        AuditEventLogger.flush();
    }

    // ── Private helpers ──────────────────────────────────────────────────────────

    private static void assertNoActivePeriodOverlap(Id dpId, Date periodStart, Date periodEnd) {
        List<Interest_Period__c> conflicts = [
            SELECT Id FROM Interest_Period__c
            WHERE Debt_Position__c = :dpId AND Status__c = 'Active'
            AND Period_End__c > :periodStart AND Period_Start__c < :periodEnd
            LIMIT 1
        ];
        if (!conflicts.isEmpty()) {
            throw new InterestPeriodException(
                'Overlapping Active Interest_Period exists for Debt Position ' + dpId + '.');
        }
    }

    public class InterestPeriodException extends Exception {}
}