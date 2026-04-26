/**
 * IDayCountCalculator
 * Implemented by: GenericDayCountCalculator (reads DayCount_Convention__mdt)
 * Returns the day count fraction: numerator_days / denominator_basis
 */
public interface IDayCountCalculator {
    /**
     * @param startDate  Period start (inclusive)
     * @param endDate    Period end (exclusive)
     * @param convention Convention code from DayCount_Convention__mdt (e.g. ACT_365)
     * @return           Decimal fraction (e.g. 1/365 for one day on ACT/365)
     */
    Decimal getDayCountFraction(Date startDate, Date endDate, String convention);
}
