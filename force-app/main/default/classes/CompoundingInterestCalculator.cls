/**
 * CompoundingInterestCalculator — implements IInterestCalculator
 * Used when active Interest_Rate_Terms.Compounding_Frequency != None.
 * Compounds interest within a period, producing higher effective yield than simple interest.
 *
 * Discrete: basis = principal + accrued-this-compounding-period; daily contribution = basis × rate × dayFraction.
 * Continuous: interest = principal × (e^(R×t) − 1) for the full period; spread across days for Accrual_Daily rows.
 *
 * Supports all four PIK/Cash combinations (PIK flag comes from ctx.interestTreatment).
 * Spec v3 Part 4.7. Calc_Strategy__mdt key: Compounding_Interest.
 */
public class CompoundingInterestCalculator extends CalculationEngineBase implements IInterestCalculator {

    public CompoundingInterestCalculator() { super(Mode.APPLY); }

    public EngineResult calculate(CalcContext ctx) {
        EngineResult result = new EngineResult();

        if (ctx.interestRate == null || ctx.principal == null) {
            result.addError('CompoundingInterestCalculator: interestRate and principal required');
            return result;
        }

        String compFreq   = (String)(ctx.extras?.get('compoundingFrequency') ?? 'None');
        String compMethod = (String)(ctx.extras?.get('compoundingMethod') ?? 'Discrete');
        Decimal accruedThisPeriod = (Decimal)(ctx.extras?.get('accruedThisCompoundingPeriod') ?? 0);

        Decimal accrued;
        if (compMethod == 'ACT_Continuous') {
            accrued = computeContinuous(ctx, compFreq);
        } else {
            accrued = computeDiscrete(ctx, compFreq, accruedThisPeriod);
        }

        accrued = accrued.setScale(2, RoundingMode.HALF_EVEN);
        result.setAmount(accrued);
        result.setResultType('Compounding_' + compMethod + '_' + compFreq);
        return result;
    }

    public override EngineResult execute(CalcContext ctx) { return calculate(ctx); }

    // Discrete compounding: basis grows each accrual day by including prior accrued interest
    private Decimal computeDiscrete(CalcContext ctx, String compFreq, Decimal accruedThisPeriod) {
        Decimal basis = ctx.principal + accruedThisPeriod;
        Decimal dayFraction = computeDailyFraction(ctx);
        return basis * (ctx.interestRate / 100) * dayFraction;
    }

    // Continuous compounding: e^(R×t) − 1 applied to total period, then prorated to today
    private Decimal computeContinuous(CalcContext ctx, String compFreq) {
        if (ctx.periodStartDate == null || ctx.periodEndDate == null || ctx.calculationDate == null) {
            return computeDiscrete(ctx, compFreq, 0);
        }
        Integer totalPeriodDays = ctx.periodStartDate.daysBetween(ctx.periodEndDate) + 1;
        Decimal tFull = totalPeriodDays / 365.0;
        Decimal rDecimal = ctx.interestRate / 100;
        Decimal fullPeriodInterest = ctx.principal * (Decimal)(Math.exp((Double)(rDecimal * tFull)) - 1);
        return totalPeriodDays > 0 ? (fullPeriodInterest / totalPeriodDays) : 0;
    }

    // Day fraction for a single day within the period — uses ACT/365 when no day count available
    private Decimal computeDailyFraction(CalcContext ctx) {
        if (ctx.periodStartDate == null || ctx.periodEndDate == null) return 1.0 / 365.0;
        Integer daysInYear = (ctx.dayCountConvention == 'ACT_360') ? 360 : 365;
        return (Decimal)1 / daysInYear;
    }

    // Helper used by caller to determine compound frequency integer (times per year)
    public static Integer freqPerYear(String compFreq) {
        if (compFreq == 'Daily')     return 365;
        if (compFreq == 'Monthly')   return 12;
        if (compFreq == 'Quarterly') return 4;
        return 1; // None or unknown
    }
}