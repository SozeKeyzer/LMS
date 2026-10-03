/**
 * SculptedAmortisationCalculator — implements IAmortisationCalculator
 * Reads Principal_Repayment_Schedules__c child records to get per-period principal amount.
 * Most flexible — for non-standard repayment profiles.
 * Expects context.extras['sculptedSchedule'] = List<Principal_Repayment_Schedules__c> pre-loaded.
 */
public class SculptedAmortisationCalculator extends CalculationEngineBase implements IAmortisationCalculator {

    public SculptedAmortisationCalculator() { super(Mode.APPLY); }

    public EngineResult calculatePrincipalRepayment(CalcContext ctx) {
        EngineResult result = new EngineResult();
        // Schedule must be pre-loaded into context to keep strategy SOQL-free
        List<Object> schedule = (List<Object>) ctx.extras.get('sculptedSchedule');
        if (schedule == null || schedule.isEmpty()) {
            // Fall back to bullet if no sculpted schedule provided
            Boolean isFinal = (Boolean)(ctx.extras.get('isFinalPeriod') ?? false);
            result.setAmount(isFinal ? ctx.principal : 0);
            result.setResultType('Sculpted_Fallback_Bullet');
            return result;
        }
        // Find the row matching this period
        Decimal due = 0;
        for (Object row : schedule) {
            Principal_Repayment_Schedules__c s = (Principal_Repayment_Schedules__c) row;
            if (s.Period_Start__c == ctx.periodStartDate) {
                due = s.Repayment_Amount__c != null ? s.Repayment_Amount__c : 0;
                break;
            }
        }
        result.setAmount(due.setScale(2, RoundingMode.HALF_EVEN));
        result.setResultType('Sculpted');
        return result;
    }

    public override EngineResult execute(CalcContext ctx) { return calculatePrincipalRepayment(ctx); }
}