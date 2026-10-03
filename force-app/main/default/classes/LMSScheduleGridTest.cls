/**
 * LMSScheduleGridTest
 * Phase 3 spec compliance tests for ScheduleGenerationService.buildPeriodGrid.
 * Tests spec Part 6.2 algorithm:
 *   periodEnd = periodStart.addMonths(freq).addDays(-1)
 *   dueDate advances independently (from firstPaymentDate + n×freq)
 *   maturityDate governs final period (spec Part 6.3)
 */
@IsTest
private class LMSScheduleGridTest {

    // Key spec invariant: period end = periodStart + freq - 1 day.
    // Due date = firstPaymentDate, NOT equal to period end.
    @IsTest
    static void testPeriodEndIsDayBeforeDueDate() {
        Date accrualStart = Date.newInstance(2026, 1, 1);
        Date firstPmt     = Date.newInstance(2026, 4, 1); // first due date
        Date maturity     = Date.newInstance(2026, 7, 1); // clean 2-period case

        List<ScheduleGenerationService.PeriodRow> grid =
            ScheduleGenerationService.buildPeriodGrid(
                accrualStart, firstPmt, maturity, 3, null, null);

        Assert.isFalse(grid.isEmpty(), 'Grid must not be empty');
        ScheduleGenerationService.PeriodRow p1 = grid[0];

        // Period end = Jan 1 + 3mo - 1day = Mar 31
        Assert.areEqual(Date.newInstance(2026, 3, 31), p1.periodEnd,
            'Period end should be periodStart + 3mo - 1day (Mar 31), not the due date (Apr 1)');

        // Due date = firstPaymentDate = Apr 1
        Assert.areEqual(Date.newInstance(2026, 4, 1), p1.dueDate,
            'Due date should be firstPaymentDate (Apr 1), independent of period end');

        // They must differ by 1 day for a standard period
        Assert.areEqual(1, p1.periodEnd.daysBetween(p1.dueDate),
            'Due date must be exactly 1 day after period end for standard periods');
    }

    // Period start of period N+1 = period end of period N + 1 day (no overlap, no gap).
    @IsTest
    static void testNoPeriodGapOrOverlap() {
        Date accrualStart = Date.newInstance(2026, 1, 1);
        Date firstPmt     = Date.newInstance(2026, 4, 1);
        Date maturity     = Date.newInstance(2026, 10, 1); // 3 periods

        List<ScheduleGenerationService.PeriodRow> grid =
            ScheduleGenerationService.buildPeriodGrid(
                accrualStart, firstPmt, maturity, 3, null, null);

        for (Integer i = 0; i < grid.size() - 1; i++) {
            ScheduleGenerationService.PeriodRow curr = grid[i];
            ScheduleGenerationService.PeriodRow next = grid[i + 1];
            Assert.areEqual(curr.periodEnd.addDays(1), next.periodStart,
                'Next period start must be the day after current period end (period ' + i + ')');
        }
    }

    // Due date advances by freq each period independently of period boundary.
    @IsTest
    static void testDueDateAdvancesIndependently() {
        Date accrualStart = Date.newInstance(2026, 1, 1);
        Date firstPmt     = Date.newInstance(2026, 4, 1);
        Date maturity     = Date.newInstance(2027, 1, 2); // enough for 4 full periods

        List<ScheduleGenerationService.PeriodRow> grid =
            ScheduleGenerationService.buildPeriodGrid(
                accrualStart, firstPmt, maturity, 3, null, null);

        Assert.isTrue(grid.size() >= 4, 'Need at least 4 periods for this test');

        // Due dates: Apr 1, Jul 1, Oct 1, Jan 1 2027 (each +3 months)
        Assert.areEqual(Date.newInstance(2026, 4,  1), grid[0].dueDate, 'Due date P1 = Apr 1');
        Assert.areEqual(Date.newInstance(2026, 7,  1), grid[1].dueDate, 'Due date P2 = Jul 1');
        Assert.areEqual(Date.newInstance(2026, 10, 1), grid[2].dueDate, 'Due date P3 = Oct 1');
        Assert.areEqual(Date.newInstance(2027, 1,  1), grid[3].dueDate, 'Due date P4 = Jan 1 2027');
    }

    // Spec Part 6.3: maturityDate governs last periodEnd.
    @IsTest
    static void testMaturityCapsPeriodEnd() {
        Date accrualStart = Date.newInstance(2026, 1, 1);
        Date firstPmt     = Date.newInstance(2026, 4, 1);
        Date maturity     = Date.newInstance(2026, 2, 15); // mid-period

        List<ScheduleGenerationService.PeriodRow> grid =
            ScheduleGenerationService.buildPeriodGrid(
                accrualStart, firstPmt, maturity, 3, null, null);

        Assert.areEqual(1, grid.size(), 'Maturity before first payment → 1 capped period');
        Assert.areEqual(maturity, grid[0].periodEnd,
            'Period end capped at maturityDate (Feb 15)');
        Assert.isTrue(grid[0].periodEnd <= maturity,
            'Period end must not exceed maturityDate');
    }

    // Spec Part 6.3: broken final period — dueDate capped at maturity when nextDueDate overshoots.
    @IsTest
    static void testBrokenFinalPeriod_DueDateCappedAtMaturity() {
        // Maturity is mid-quarter; due date would overshoot to Apr 1 if not capped
        Date accrualStart = Date.newInstance(2026, 1, 1);
        Date firstPmt     = Date.newInstance(2026, 4, 1);
        Date maturity     = Date.newInstance(2026, 2, 15); // Feb 15 maturity

        List<ScheduleGenerationService.PeriodRow> grid =
            ScheduleGenerationService.buildPeriodGrid(
                accrualStart, firstPmt, maturity, 3, null, null);

        Assert.areEqual(1, grid.size());
        Assert.areEqual(maturity, grid[0].dueDate,
            'Broken final period: due date must equal maturityDate (Feb 15), not Apr 1');
    }

    // Spec Part 6.2: accrualStartDate is the period anchor, not firstPaymentDate - freq.
    // When accrualStart differs from firstPaymentDate - freq, a broken first period is produced.
    @IsTest
    static void testAccrualStartDateIsAnchor() {
        // Accrual starts Feb 1, first payment Apr 1 (2-month broken first period)
        Date accrualStart = Date.newInstance(2026, 2, 1);
        Date firstPmt     = Date.newInstance(2026, 4, 1);
        Date maturity     = Date.newInstance(2026, 10, 1);

        List<ScheduleGenerationService.PeriodRow> grid =
            ScheduleGenerationService.buildPeriodGrid(
                accrualStart, firstPmt, maturity, 3, null, null);

        // Period 1 must start at accrualStart, not at firstPmt - 3 months
        Assert.areEqual(accrualStart, grid[0].periodStart,
            'Period 1 start must be Accrual_Start_Date, not firstPaymentDate - freq');
        // Due date for period 1 = firstPaymentDate
        Assert.areEqual(firstPmt, grid[0].dueDate,
            'Period 1 due date must still be firstPaymentDate');
    }

    // Annual frequency: basic 2-period schedule
    @IsTest
    static void testAnnualFrequency_TwoPeriods() {
        Date accrualStart = Date.newInstance(2025, 1, 1);
        Date firstPmt     = Date.newInstance(2026, 1, 1);
        Date maturity     = Date.newInstance(2027, 1, 2); // cover 2 full annual periods

        List<ScheduleGenerationService.PeriodRow> grid =
            ScheduleGenerationService.buildPeriodGrid(
                accrualStart, firstPmt, maturity, 12, null, null);

        Assert.isTrue(grid.size() >= 2, 'Annual freq should produce at least 2 periods');
        // Period 1 end = Jan 1 + 12mo - 1day = Dec 31, 2025
        Assert.areEqual(Date.newInstance(2025, 12, 31), grid[0].periodEnd,
            'Annual period 1 end: Jan 1, 2025 + 12mo - 1day = Dec 31, 2025');
        Assert.areEqual(firstPmt, grid[0].dueDate,
            'Annual period 1 due date = firstPaymentDate');
    }
}