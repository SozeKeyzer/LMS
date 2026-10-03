/**
 * AmendmentService
 *
 * End-to-end amendment workflow (spec §5.5.3). Three public entry points:
 *
 *   generatePreview(amendmentId)
 *       Called from the Amendment_Wizard LWC (via AmendmentProjectionComparisonController)
 *       before submission. Runs the calculation engine in PREVIEW mode across all open
 *       Payment_Schedule periods from the proposed effective date forward, using the new
 *       Pending IRT (rate amendments) or the current Applied IRT (structural amendments).
 *       Creates a Projection__c via ProjectionService and links it to the amendment via
 *       Recalc_Projection__c. Required before submission per VR.LA.04.
 *
 *   captureBeforeState(la)
 *       Called from LoanAmendmentHandler.beforeUpdate when Status → Effective.
 *       Queries the current state of affected DPs before any commit DML runs
 *       and returns a JSON string for storage in Before_State__c.
 *
 *   executeCommit(la)
 *       Called from LoanAmendmentHandler.afterUpdate when Status → Effective.
 *       Supersedes open Payment_Schedule rows from the effective date forward,
 *       clears In_Amendment flags on DP(s) and the parent FI (when all resolved),
 *       and writes the After_State__c snapshot on the amendment record.
 *       The IRT lifecycle (Pending → Applied / Superseded) is handled separately
 *       through the standard rate application workflow (RateApplicationService).
 *
 * Supports Scope = 'Position' (single DP) and Scope = 'Facility' (all DPs under the parent FI
 * that still have In_Amendment__c = true).
 */
public class AmendmentService {

    // ─────────────────────────────────────────────────────────────────────────
    // Preview generation — called from Amendment_Wizard LWC before submission
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Runs the calculation engine in PREVIEW mode and creates the Projection__c record
     * required by VR.LA.04 before submission.
     *
     * For Rate_Change / Margin_Ratchet: uses the Pending Amendment IRT (new terms ops
     * created before opening the amendment). For structural amendments (Tenor_Extension,
     * Principal_Increase etc.): uses the current Applied IRT so the projection reflects
     * today's rate against the revised period structure.
     *
     * Interest is recomputed per period via IInterestCalculator. Principal is taken from
     * the existing Payment_Schedule rows (rate amendments do not alter the principal
     * schedule — that is regenerated separately if needed after commit).
     */
    public static Id generatePreview(Id amendmentId) {
        if (amendmentId == null) {
            throw new AuraHandledException('Amendment Id is required.');
        }

        List<Loan_Amendment__c> laList = [
            SELECT Id, Name, Scope__c, Amendment_Type__c,
                   Debt_Position__c, Financial_Instrument__c,
                   Proposed_Effective_Date__c
            FROM Loan_Amendment__c WHERE Id = :amendmentId LIMIT 1
        ];
        if (laList.isEmpty()) return null;
        Loan_Amendment__c la = laList[0];

        // Resolve the primary DP for the projection (Position = direct; Facility = first In_Amendment DP)
        Id dpId = la.Debt_Position__c;
        if (dpId == null && la.Financial_Instrument__c != null) {
            List<Debt_Position__c> facilityDps = [
                SELECT Id FROM Debt_Position__c
                WHERE Financial_Instrument__c = :la.Financial_Instrument__c
                  AND In_Amendment__c = true
                LIMIT 1
            ];
            if (!facilityDps.isEmpty()) dpId = facilityDps[0].Id;
        }
        if (dpId == null) {
            throw new AuraHandledException(
                'No Debt Position resolved for this amendment. ' +
                'For a Position-scope amendment ensure Debt Position is set. ' +
                'For a Facility-scope amendment ensure at least one Debt Position has In Amendment = true.');
        }

        Debt_Position__c dp = [
            SELECT Id, Outstanding_Balance__c, Position_Notional__c, Day_Count_Convention__c
            FROM Debt_Position__c WHERE Id = :dpId LIMIT 1
        ];

        // Preview date: use the proposed effective date; fall back to today
        Date previewDate = la.Proposed_Effective_Date__c != null
            ? la.Proposed_Effective_Date__c : Date.today();

        // Prefer the new Pending IRT (rate amendments). Fall back to current Applied IRT
        // for structural amendments where the rate is unchanged.
        List<Interest_Rate_Terms__c> pendingIrts = [
            SELECT Id, Pricing_Basis__c, Applicable_Fixed_Rate__c, Spread__c,
                   Base_Rate_Value__c, Floor_Rate__c, Ceiling_Rate__c
            FROM Interest_Rate_Terms__c
            WHERE Debt_Position__c = :dpId
              AND Application_Status__c = 'Pending'
              AND Rate_Reset_Trigger__c = 'Amendment'
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        List<Interest_Rate_Terms__c> appliedIrts = [
            SELECT Id, Pricing_Basis__c, Applicable_Fixed_Rate__c, Spread__c,
                   Base_Rate_Value__c, Floor_Rate__c, Ceiling_Rate__c
            FROM Interest_Rate_Terms__c
            WHERE Debt_Position__c = :dpId
              AND Application_Status__c = 'Applied'
            ORDER BY Actual_Application_Date__c DESC NULLS LAST LIMIT 1
        ];
        Interest_Rate_Terms__c previewIrt = !pendingIrts.isEmpty() ? pendingIrts[0]
            : (!appliedIrts.isEmpty() ? appliedIrts[0] : null);
        if (previewIrt == null) {
            throw new AuraHandledException(
                'No Interest Rate Terms found for this Debt Position. ' +
                'Rate Change / Margin Ratchet / DayCount Change amendments require a Pending IRT with ' +
                'Rate Reset Trigger = Amendment. ' +
                'Structural amendments (Tenor Extension, Principal Increase etc.) require an Applied IRT.');
        }

        // Future Payment_Schedule rows — provide period boundaries for the projection
        List<Payment_Schedule__c> futurePs = [
            SELECT Id, Period_Start__c, Period_End__c, Due_Date__c, Principal_Due__c
            FROM Payment_Schedule__c
            WHERE Debt_Position__c = :dpId
              AND Status__c IN ('Projected', 'Due')
              AND Period_Start__c >= :previewDate
            ORDER BY Period_Start__c ASC
        ];
        if (futurePs.isEmpty()) {
            throw new AuraHandledException(
                'No open Payment Schedule rows found on or after ' + previewDate + '. ' +
                'Ensure the loan has Projected or Due schedule rows from the proposed effective date onwards.');
        }

        // Build calculation parameters
        String pricingBasis = String.isNotBlank(previewIrt.Pricing_Basis__c)
            ? previewIrt.Pricing_Basis__c : 'Floating';

        // Calculators expect rate as whole-number percentage (e.g. 6.5 for 6.5%).
        // Fixed:    Applicable_Fixed_Rate__c is the all-in rate — no benchmark.
        // Floating: Base_Rate_Value__c (benchmark, manually entered on IRT) + Spread__c (margin),
        //           then Floor_Rate__c / Ceiling_Rate__c applied.
        //           If Base_Rate_Value__c is null, falls back to spread-only.
        Decimal previewRate;
        if (pricingBasis == 'Fixed') {
            if (previewIrt.Applicable_Fixed_Rate__c == null) {
                throw new AuraHandledException(
                    'No rate value found on the Interest Rate Terms record. ' +
                    'For Fixed rate: populate Applicable Fixed Rate.');
            }
            Decimal raw = previewIrt.Applicable_Fixed_Rate__c;
            previewRate = raw < 1 ? raw * 100 : raw;
        } else {
            if (previewIrt.Spread__c == null) {
                throw new AuraHandledException(
                    'No rate value found on the Interest Rate Terms record. ' +
                    'For Floating rate: populate Spread.');
            }
            Decimal baseRate = previewIrt.Base_Rate_Value__c != null ? previewIrt.Base_Rate_Value__c : 0;
            Decimal raw = baseRate + previewIrt.Spread__c;
            if (previewIrt.Floor_Rate__c != null && raw < previewIrt.Floor_Rate__c) raw = previewIrt.Floor_Rate__c;
            if (previewIrt.Ceiling_Rate__c != null && raw > previewIrt.Ceiling_Rate__c) raw = previewIrt.Ceiling_Rate__c;
            previewRate = raw < 1 ? raw * 100 : raw;
        }

        Decimal principal = dp.Outstanding_Balance__c != null && dp.Outstanding_Balance__c != 0
            ? dp.Outstanding_Balance__c
            : (dp.Position_Notional__c != null ? dp.Position_Notional__c : null);
        if (principal == null || principal == 0) {
            throw new AuraHandledException(
                'Outstanding Balance is 0 or not set on the Debt Position. ' +
                'Populate Outstanding Balance (or Position Notional as fallback) before generating a preview.');
        }

        String dayCountConv = String.isNotBlank(dp.Day_Count_Convention__c)
            ? dp.Day_Count_Convention__c : 'ACT_365';
        String corrId = TriggerContext.getInstance().correlationId;

        // Strategy calculator — resolved once, cached by factory after first call
        IInterestCalculator interestCalc =
            CalculationEngineFactory.getInterestCalculator(pricingBasis);

        List<Map<String, Object>> projectedRows = new List<Map<String, Object>>();
        for (Payment_Schedule__c ps : futurePs) {
            CalcContext ctx = new CalcContext.Builder()
                .setDebtPositionId(dpId)
                .setPrincipal(principal)
                .setInterestRate(previewRate)
                .setDayCountConvention(dayCountConv)
                .setInterestTreatment(pricingBasis)
                .setPeriodStartDate(ps.Period_Start__c)
                .setPeriodEndDate(ps.Period_End__c)
                .setCalculationDate(ps.Due_Date__c)
                .setCorrelationId(corrId)
                .setEngineMode('PREVIEW')
                .build();

            EngineResult r    = interestCalc.calculate(ctx);
            Decimal projInterest  = r.success ? r.calculatedAmount : null;
            // Rate amendments leave the principal schedule unchanged
            Decimal projPrincipal = ps.Principal_Due__c;
            Decimal projTotal = (projInterest != null && projPrincipal != null)
                ? projInterest + projPrincipal : null;

            projectedRows.add(new Map<String, Object>{
                'periodStart'  => String.valueOf(ps.Period_Start__c),
                'periodEnd'    => String.valueOf(ps.Period_End__c),
                'dueDate'      => String.valueOf(ps.Due_Date__c),
                'principalDue' => projPrincipal,
                'interestDue'  => projInterest,
                'totalDue'     => projTotal,
                'status'       => 'Projected'
            });
        }

        Projection__c proj = ProjectionService.generateForAmendment(dpId, la.Id, projectedRows);

        // Link projection to the amendment — bypassGuards because guard handler blocks
        // system-initiated updates on Loan_Amendment__c the same as it does on DP/FI.
        TriggerContext.getInstance().bypassGuards = true;
        try {
            update new Loan_Amendment__c(Id = la.Id, Recalc_Projection__c = proj.Id);
        } finally {
            TriggerContext.getInstance().bypassGuards = false;
        }

        AuditEventLogger.logEngine(
            'ENGINE_RUN_PREVIEW', 'Loan_Amendment__c', String.valueOf(la.Id),
            'Preview projection generated. Periods=' + projectedRows.size()
            + '. IRT=' + previewIrt.Id + '. Projection=' + proj.Id
            + '. Rate=' + previewRate + '. Basis=' + pricingBasis);
        AuditEventLogger.flush();

        return proj.Id;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Before-state capture — called in before-update context
    // ─────────────────────────────────────────────────────────────────────────

    public static String captureBeforeState(Loan_Amendment__c la) {
        List<Debt_Position__c> dps = resolveDPs(la);
        Map<String, Object> snapshot = new Map<String, Object>{
            'scope'         => la.Scope__c,
            'capturedAt'    => String.valueOf(System.now()),
            'debtPositions' => serializeDPs(dps)
        };
        return JSON.serialize(snapshot);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Commit — called in after-update context
    // ─────────────────────────────────────────────────────────────────────────

    public static void executeCommit(Loan_Amendment__c la) {
        List<Debt_Position__c> dps = resolveDPs(la);
        if (dps.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'AmendmentService.executeCommit: no DPs resolved for amendment ' + la.Id +
                ' (Scope=' + la.Scope__c + ')');
            return;
        }

        Set<Id> dpIds = new Map<Id, Debt_Position__c>(dps).keySet();
        Integer supersededCount  = supersedePsRows(dpIds, la);
        Integer regeneratedCount = PaymentScheduleService.regenerateAfterAmendment(dpIds, la);

        TriggerContext.getInstance().bypassGuards = true;
        try {
            // Clear DP-level In_Amendment flags
            List<Debt_Position__c> dpUpdates = new List<Debt_Position__c>();
            for (Debt_Position__c dp : dps) {
                dpUpdates.add(new Debt_Position__c(Id = dp.Id, In_Amendment__c = false));
            }
            update dpUpdates;

            // Clear FI-level flag when no other DPs remain In Amendment under this FI
            Id fiId = dps[0].Financial_Instrument__c;
            if (fiId != null) {
                clearFiFlag(fiId, dpIds);
            }

            // Write After_State snapshot on the amendment — separate DML from DP/FI updates
            // to keep concerns isolated; bypassGuards prevents the guard handler from
            // blocking this system-initiated update.
            update new Loan_Amendment__c(
                Id             = la.Id,
                After_State__c = JSON.serialize(new Map<String, Object>{
                    'scope'                => la.Scope__c,
                    'supersededSchedules'  => supersededCount,
                    'regeneratedSchedules' => regeneratedCount,
                    'actualEffectiveDate'  => String.valueOf(la.Actual_Effective_Date__c),
                    'dpCount'              => dps.size()
                })
            );
        } finally {
            TriggerContext.getInstance().bypassGuards = false;
        }

        AuditEventLogger.logEngine(
            'AMENDMENT_COMMITTED', 'Loan_Amendment__c', String.valueOf(la.Id),
            'Amendment committed. Scope=' + la.Scope__c +
            '. DPs=' + dps.size() +
            '. Schedules superseded=' + supersededCount + '.');
        AuditEventLogger.flush();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────────────────────────────────────

    private static List<Debt_Position__c> resolveDPs(Loan_Amendment__c la) {
        if (la.Scope__c == 'Position' && la.Debt_Position__c != null) {
            return [
                SELECT Id, Name, Status__c, Financial_Instrument__c,
                       Initial_Margin__c, Initial_Benchmark__c,
                       Initial_Rate_Floor__c, Initial_Rate_Ceiling__c,
                       PIK_Default_Mode__c, Interest_Reserve_Default_Mode__c,
                       In_Amendment__c
                FROM Debt_Position__c
                WHERE Id = :la.Debt_Position__c
                FOR UPDATE
            ];
        }
        if (la.Scope__c == 'Facility' && la.Financial_Instrument__c != null) {
            return [
                SELECT Id, Name, Status__c, Financial_Instrument__c,
                       Initial_Margin__c, Initial_Benchmark__c,
                       Initial_Rate_Floor__c, Initial_Rate_Ceiling__c,
                       PIK_Default_Mode__c, Interest_Reserve_Default_Mode__c,
                       In_Amendment__c
                FROM Debt_Position__c
                WHERE Financial_Instrument__c = :la.Financial_Instrument__c
                  AND In_Amendment__c = true
                FOR UPDATE
            ];
        }
        return new List<Debt_Position__c>();
    }

    private static Integer supersedePsRows(Set<Id> dpIds, Loan_Amendment__c la) {
        List<Payment_Schedule__c> toSupersede = [
            SELECT Id
            FROM Payment_Schedule__c
            WHERE Debt_Position__c IN :dpIds
              AND Status__c IN ('Projected', 'Due')
              AND Period_Start__c >= :la.Actual_Effective_Date__c
        ];
        if (toSupersede.isEmpty()) return 0;

        String reason = 'Amendment ' + la.Name + ' — ' + la.Amendment_Type__c;
        String laId   = String.valueOf(la.Id);
        List<Payment_Schedule__c> updates = new List<Payment_Schedule__c>();
        for (Payment_Schedule__c ps : toSupersede) {
            updates.add(new Payment_Schedule__c(
                Id                           = ps.Id,
                Status__c                    = 'Superseded',
                Is_Immutable__c              = true,         // per spec 9.4 — immutable once superseded
                Supersession_Reason__c       = reason,
                Supersession_Amendment_Id__c = laId
            ));
        }
        update updates;
        return updates.size();
    }

    // Clears FI.In_Amendment__c only when no other DPs under the same FI remain in amendment.
    // committedDpIds are excluded from the count because they were just updated in this transaction;
    // their in-DB In_Amendment__c value is now false, so the NOT IN clause is a safety net.
    private static void clearFiFlag(Id fiId, Set<Id> committedDpIds) {
        Integer remaining = [
            SELECT COUNT()
            FROM Debt_Position__c
            WHERE Financial_Instrument__c = :fiId
              AND In_Amendment__c = true
              AND Id NOT IN :committedDpIds
        ];
        if (remaining == 0) {
            update new Financial_Instrument__c(Id = fiId, In_Amendment__c = false);
        }
    }

    private static List<Map<String, Object>> serializeDPs(List<Debt_Position__c> dps) {
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (Debt_Position__c dp : dps) {
            out.add(new Map<String, Object>{
                'id'                         => dp.Id,
                'name'                       => dp.Name,
                'status'                     => dp.Status__c,
                'initialMargin'              => dp.Initial_Margin__c,
                'initialBenchmark'           => dp.Initial_Benchmark__c,
                'initialRateFloor'           => dp.Initial_Rate_Floor__c,
                'initialRateCeiling'         => dp.Initial_Rate_Ceiling__c,
                'pikDefaultMode'             => dp.PIK_Default_Mode__c,
                'interestReserveDefaultMode' => dp.Interest_Reserve_Default_Mode__c
            });
        }
        return out;
    }
}