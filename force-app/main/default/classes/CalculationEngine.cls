/**
 * CalculationEngine
 * Main orchestrator. Selects strategies via CalculationEngineFactory.
 * Enforces Preview/Apply mode contract — strategies never know which mode.
 * Enforces Rule R10 via CalculationEngineBase.isEngineOwned() before every write.
 */
public class CalculationEngine extends CalculationEngineBase {

    public CalculationEngine(Mode m) {
        super(m);
    }

    /**
     * Execute interest calculation for a given CalcContext.
     * Strategy selected by CalcContext.interestTreatment.
     */
    public override EngineResult execute(CalcContext ctx) {
        AuditEventLogger.logEngine('ENGINE_RUN_PREVIEW', 'Debt_Position__c',
            ctx.debtPositionId, 'Engine started | Mode: ' + executionMode + ' | CorrelationId: ' + ctx.correlationId);

        EngineResult result = new EngineResult();

        try {
            // Day count first — needed by all interest strategies
            IDayCountCalculator dayCount = CalculationEngineFactory.getDayCountCalculator();
            Decimal fraction = dayCount.getDayCountFraction(
                ctx.periodStartDate, ctx.periodEndDate, ctx.dayCountConvention);
            result.putMeta('dayCountFraction', fraction);

            // Interest calculation
            IInterestCalculator interestCalc =
                CalculationEngineFactory.getInterestCalculator(ctx.interestTreatment);
            EngineResult interestResult = interestCalc.calculate(ctx);
            result.setAmount(interestResult.calculatedAmount);
            for (SObject r : interestResult.recordsToInsert) result.addInsert(r);

            // Amortisation
            if (String.isNotBlank(ctx.amortisationMethod)) {
                IAmortisationCalculator amortCalc =
                    CalculationEngineFactory.getAmortisationCalculator(ctx.amortisationMethod);
                EngineResult amortResult = amortCalc.calculatePrincipalRepayment(ctx);
                result.putMeta('principalDue', amortResult.calculatedAmount);
                for (SObject r : amortResult.recordsToInsert) result.addInsert(r);
            }

        } catch (Exception e) {
            result.addError(e.getMessage());
            AuditEventLogger.logEngine('ENGINE_RUN_PREVIEW', 'Debt_Position__c',
                ctx.debtPositionId, 'Engine error: ' + e.getMessage());
        }

        if (result.success) {
            commitResult(result);
            AuditEventLogger.logEngine('ENGINE_RUN_COMMIT', 'Debt_Position__c',
                ctx.debtPositionId, 'Engine completed | Amount: ' + result.calculatedAmount);
        }
        AuditEventLogger.flush();
        return result;
    }

    /**
     * Post a single day's accrual for a Debt Position.
     * Called by DailyAccrualBatch per DP per day.
     */
    public EngineResult postDailyAccrual(Date accrualDate, CalcContext ctx) {
        IAccrualPoster poster = CalculationEngineFactory.getAccrualPoster();
        EngineResult result = poster.postDailyAccrual(accrualDate, ctx);
        if (result.success && isApply()) {
            commitResult(result);
        }
        AuditEventLogger.flush();
        return result;
    }
}