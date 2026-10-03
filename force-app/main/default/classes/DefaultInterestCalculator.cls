/**
 * DefaultInterestCalculator — implements IInterestCalculator
 * Interest-on-interest (default interest compounding) per Spec v3 Part 8.6 and Rule R20.
 *
 * Used when Debt_Position.Is_In_Default__c = true AND the active Default Interest
 * IRT row (Rate_Segment_Type = Default_Interest) has Default_Interest_Compounding__c = true.
 *
 * The accrual basis each day = Outstanding_Balance + sum of Accrual_Daily where:
 *   Status = Accrued AND parent Payment_Schedule.Due_Date < accrualDate
 *   AND parent Payment_Schedule.Status NOT IN (Paid, Settled_PIK)
 *
 * This is a recursive growth: each day's accrual grows the unpaid balance used
 * the next day. SOQL for unpaid accrued interest is pre-loaded by caller into
 * ctx.extras['unpaidAccruedInterest'] to keep strategy SOQL-free.
 */
public class DefaultInterestCalculator extends CalculationEngineBase implements IInterestCalculator {

    public DefaultInterestCalculator() { super(Mode.APPLY); }

    public EngineResult calculate(CalcContext ctx) {
        EngineResult result = new EngineResult();

        if (ctx.interestRate == null || ctx.principal == null) {
            result.addError('DefaultInterestCalculator: interestRate and principal required');
            return result;
        }

        Boolean compoundIoI     = (Boolean)(ctx.extras?.get('defaultInterestCompounding') ?? false);
        String  compFreq        = (String)(ctx.extras?.get('compoundingFrequency') ?? 'None');
        Decimal unpaidAccrued   = (Decimal)(ctx.extras?.get('unpaidAccruedInterest') ?? 0);

        // Basis = outstanding principal (always) + unpaid accrued interest (only when IoI active)
        Decimal basis = ctx.principal;
        if (compoundIoI && unpaidAccrued > 0) {
            basis = basis + unpaidAccrued;
        }

        // On_Cure mode: accumulate at simple interest; compound only at cure (handled externally)
        // All other modes: daily accrual on the growing basis
        Decimal dayFraction = computeDailyFraction(ctx);
        Decimal accrued = (basis * (ctx.interestRate / 100) * dayFraction).setScale(2, RoundingMode.HALF_EVEN);

        result.setAmount(accrued);
        result.setResultType('DefaultInterest' + (compoundIoI ? '_IoI_' + compFreq : '_Simple'));
        return result;
    }

    public override EngineResult execute(CalcContext ctx) { return calculate(ctx); }

    private Decimal computeDailyFraction(CalcContext ctx) {
        Integer daysInYear = (ctx.dayCountConvention == 'ACT_360') ? 360 : 365;
        return (Decimal)1 / daysInYear;
    }

    /**
     * Queries unpaid accrued interest for a DP as of a given accrual date.
     */
    public static Decimal queryUnpaidAccruedInterest(Id dpId, Date accrualDate) {
        AggregateResult[] agg = [
            SELECT SUM(Accrued_Amount__c) total
            FROM Accrual_Daily__c
            WHERE Debt_Position__c = :dpId
              AND Status__c = 'Accrued'
              AND Accrual_Date__c < :accrualDate
        ];
        if (agg == null || agg.isEmpty() || agg[0].get('total') == null) return 0;
        return (Decimal) agg[0].get('total');
    }
}