/**
 * ScheduleReamortisationService
 * Re-amortises future Payment_Schedule rows after a Disbursement_Event clears (DDTL)
 * or after a Fee_Capitalisation_Event activates (notional uplift).
 *
 * Mode dispatch per Drawdown_Reamortisation_Mode on Debt_Position:
 *   Re-Amortise_Forward — supersede future rows; regenerate using current Outstanding_Balance
 *   Bullet_Hold         — no schedule change; balance update and accrual pick it up naturally
 *   Manual              — notify ops; no automatic schedule action
 *
 * Spec v3 Part 6.6, v7 Rule R19 / Part 5.2.1.3.
 */
public class ScheduleReamortisationService {

    /**
     * Called on Disbursement_Event status → Cleared.
     * Entry point from DisbursementService or trigger handler.
     */
    public static void onDisbursementCleared(Id disbursementId) {
        Disbursement_Event__c d = [
            SELECT Id, Debt_Position__c, Amount__c, Value_Date__c, Correlation_Id__c
            FROM Disbursement_Event__c
            WHERE Id = :disbursementId
        ];
        Debt_Position__c dp = [
            SELECT Id, Drawdown_Reamortisation_Mode__c, Outstanding_Balance__c,
                   Position_Notional__c, Position_Maturity_Date__c,
                   Schedule_Generation_Status__c
            FROM Debt_Position__c
            WHERE Id = :d.Debt_Position__c
        ];

        // Only act when schedule is Active
        if (dp.Schedule_Generation_Status__c != 'Active') {
            AuditEventLogger.logEngine('SCHEDULE_REAMORTISED', 'Debt_Position__c',
                String.valueOf(dp.Id),
                'Schedule not Active — skipping re-amortisation for disbursement ' + disbursementId);
            AuditEventLogger.flush();
            return;
        }

        String mode = dp.Drawdown_Reamortisation_Mode__c;
        if (mode == 'Bullet_Hold' || mode == null) {
            AuditEventLogger.logEngine('SCHEDULE_REAMORTISED', 'Debt_Position__c',
                String.valueOf(dp.Id), 'Bullet_Hold mode; no schedule re-amortisation');
            AuditEventLogger.flush();
            return;
        }
        if (mode == 'Manual') {
            NotificationService.fire('Drawdown_Manual_Action_Required', dp);
            AuditEventLogger.logEngine('SCHEDULE_REAMORTISED', 'Debt_Position__c',
                String.valueOf(dp.Id), 'Manual mode; ops notified');
            AuditEventLogger.flush();
            return;
        }
        if (mode == 'Re-Amortise_Forward') {
            String corrId = String.isNotBlank(d.Correlation_Id__c)
                ? d.Correlation_Id__c : CorrelationIdGenerator.generate();
            reamortiseForward(dp, d.Value_Date__c, d.Amount__c, corrId);
            return;
        }
        throw new ReamortisationException('Unknown Drawdown_Reamortisation_Mode: ' + mode);
    }

    /**
     * Called by FeeCapitalisationService after Position_Notional is uplifted.
     * Re-generates future schedule rows using the new notional.
     */
    public static void reamortiseAfterEvent(Id dpId, Date effectiveDate, String correlationId) {
        Debt_Position__c dp = [
            SELECT Id, Drawdown_Reamortisation_Mode__c, Outstanding_Balance__c,
                   Position_Notional__c, Position_Maturity_Date__c, Schedule_Generation_Status__c
            FROM Debt_Position__c
            WHERE Id = :dpId
        ];
        if (dp.Schedule_Generation_Status__c != 'Active') return;
        reamortiseForward(dp, effectiveDate, null, correlationId);
    }

    // ── Core re-amortisation logic ────────────────────────────────────────────

    private static void reamortiseForward(Debt_Position__c dp, Date valueDate,
                                          Decimal disbursedAmount, String correlationId) {
        // 1. Identify future rows to supersede (Period_Start >= valueDate, not already terminal)
        List<Payment_Schedule__c> futureRows = [
            SELECT Id, Period_Start__c, Period_End__c, Due_Date__c, Status__c, Fees_Due__c,
                   Rate_Finalisation_Status__c, Placeholder_Base_Rate__c, Placeholder_Spread__c
            FROM Payment_Schedule__c
            WHERE Debt_Position__c = :dp.Id
              AND Period_Start__c >= :valueDate
              AND Status__c NOT IN ('Paid', 'Settled_PIK', 'Superseded', 'Cancelled', 'Waived')
            ORDER BY Period_Start__c ASC
        ];
        if (futureRows.isEmpty()) {
            AuditEventLogger.logEngine('SCHEDULE_REAMORTISED', 'Debt_Position__c',
                String.valueOf(dp.Id), 'No future periods to re-amortise as of ' + valueDate);
            AuditEventLogger.flush();
            return;
        }

        // 2. Build and insert replacement rows first — we need their IDs for Superseded_By__c
        String disbursedNote = disbursedAmount != null
            ? 'Re-amortised after drawdown of ' + disbursedAmount + ' on ' + valueDate
            : 'Re-amortised after notional event effective ' + valueDate;

        Decimal newPrincipal = dp.Outstanding_Balance__c != null ? dp.Outstanding_Balance__c : 0;

        List<Payment_Schedule__c> newRows = buildReplacementRows(
            dp, futureRows, newPrincipal, correlationId, disbursedNote);

        TriggerContext.getInstance().bypassGuards = true;
        try {
            if (!newRows.isEmpty()) insert newRows;
        } finally {
            TriggerContext.getInstance().bypassGuards = false;
        }

        // 3. Map Period_Start__c → new row Id so old rows can reference their replacement
        Map<Date, Id> newRowByPeriodStart = new Map<Date, Id>();
        for (Payment_Schedule__c nr : newRows) {
            newRowByPeriodStart.put(nr.Period_Start__c, nr.Id);
        }

        // 4. Mark existing future rows Superseded — VR_PS_04 requires Superseded_By__c
        for (Payment_Schedule__c ps : futureRows) {
            ps.Status__c = 'Superseded';
            ps.Is_Immutable__c = true;
            ps.Superseded_By__c = newRowByPeriodStart.get(ps.Period_Start__c);
        }
        TriggerContext.getInstance().bypassGuards = true;
        try {
            update futureRows;
        } finally {
            TriggerContext.getInstance().bypassGuards = false;
        }

        AuditEventLogger.logEngine('SCHEDULE_REAMORTISED', 'Debt_Position__c', String.valueOf(dp.Id),
            futureRows.size() + ' rows superseded; ' + newRows.size()
                + ' fresh rows generated. New basis: ' + newPrincipal
                + '. ' + disbursedNote);
        NotificationService.fire('Schedule_Reamortised_After_Drawdown', dp);
        AuditEventLogger.flush();
    }

    private static List<Payment_Schedule__c> buildReplacementRows(
        Debt_Position__c dp,
        List<Payment_Schedule__c> oldRows,
        Decimal newPrincipal,
        String correlationId,
        String sourceNote
    ) {
        Integer n = oldRows.size();
        if (n == 0) return new List<Payment_Schedule__c>();

        // Equal-principal split over remaining periods (same method as default re-amort)
        Decimal perPeriod = n > 0 ? (newPrincipal / n).setScale(2, RoundingMode.HALF_EVEN) : 0;
        Date today = Date.today();
        List<Payment_Schedule__c> newRows = new List<Payment_Schedule__c>();

        for (Integer i = 0; i < n; i++) {
            Payment_Schedule__c old = oldRows[i];
            Boolean isLast = (i == n - 1);
            // Last period absorbs rounding residual
            Decimal principal = isLast
                ? (newPrincipal - (perPeriod * (n - 1))).setScale(2, RoundingMode.HALF_EVEN)
                : perPeriod;

            String rateFinalStatus = old.Rate_Finalisation_Status__c != null
                ? old.Rate_Finalisation_Status__c : 'Not_Applicable';

            newRows.add(new Payment_Schedule__c(
                Debt_Position__c                = dp.Id,
                Period_Start__c                 = old.Period_Start__c,
                Period_End__c                   = old.Period_End__c,
                Due_Date__c                     = old.Due_Date__c,
                Principal_Due__c                = principal,
                Interest_Due__c                 = 0,
                Fees_Due__c                     = old.Fees_Due__c != null ? old.Fees_Due__c : 0,
                Status__c                       = old.Period_End__c < today ? 'Paid' : 'Due',
                Rate_Finalisation_Status__c     = rateFinalStatus,
                Placeholder_Base_Rate__c        = old.Placeholder_Base_Rate__c,
                Placeholder_Spread__c           = old.Placeholder_Spread__c,
                Is_Immutable__c                 = false,
                Source__c                       = 'System_Calculated',
                Source_Note__c                  = sourceNote,
                Correlation_Id__c               = correlationId,
                Engine_Version__c               = CalculationEngineBase.ENGINE_VERSION,
                External_Id__c                  = String.valueOf(dp.Id) + '-'
                    + old.Period_Start__c.format() + '-RA-' + correlationId.right(8)
            ));
        }
        return newRows;
    }

    public class ReamortisationException extends Exception {}
}