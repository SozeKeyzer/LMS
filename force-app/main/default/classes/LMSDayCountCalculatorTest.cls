/**
 * LMSDayCountCalculatorTest
 * Phase 3 spec compliance tests for GenericDayCountCalculator.
 * All assertions derive from spec document Part 3.2 worked examples and Part 3.4.
 * Requires deployed DayCount_Convention__mdt records (all 5 conventions).
 */
@IsTest
private class LMSDayCountCalculatorTest {

    // Spec Part 3.2.1: ACT/360. 31 Mar to 30 Jun 2026 = 91 days. Fraction = 91/360 = 0.252778
    @IsTest
    static void testACT360_SpecExample() {
        GenericDayCountCalculator calc = new GenericDayCountCalculator();
        Decimal fraction = calc.getDayCountFraction(
            Date.newInstance(2026, 3, 31),
            Date.newInstance(2026, 6, 30),
            'ACT_360'
        );
        Assert.areEqual(
            (91.0 / 360.0).setScale(6, RoundingMode.HALF_UP),
            fraction.setScale(6, RoundingMode.HALF_UP),
            'ACT/360: 91 days / 360 should match spec 3.2.1 (≈ 0.252778)'
        );
    }

    // Spec Part 3.2.2: ACT/365. Same period = 91/365 = 0.249315
    @IsTest
    static void testACT365_SpecExample() {
        GenericDayCountCalculator calc = new GenericDayCountCalculator();
        Decimal fraction = calc.getDayCountFraction(
            Date.newInstance(2026, 3, 31),
            Date.newInstance(2026, 6, 30),
            'ACT_365'
        );
        Assert.areEqual(
            (91.0 / 365.0).setScale(6, RoundingMode.HALF_UP),
            fraction.setScale(6, RoundingMode.HALF_UP),
            'ACT/365: 91 days / 365 should match spec 3.2.2 (≈ 0.249315)'
        );
    }

    // Spec Part 3.2.3: THIRTY/360 US. 31 Mar → 30 Jun. D1=31→30; D2=30 (unchanged).
    // Numerator = 360×0 + 30×(6-3) + (30-30) = 90. Fraction = 90/360 = 0.25
    @IsTest
    static void testTHIRTY360US_SpecExample() {
        GenericDayCountCalculator calc = new GenericDayCountCalculator();
        Decimal fraction = calc.getDayCountFraction(
            Date.newInstance(2026, 3, 31),
            Date.newInstance(2026, 6, 30),
            'THIRTY_360_US'
        );
        Assert.areEqual(
            0.25,
            fraction.setScale(6, RoundingMode.HALF_UP),
            'THIRTY/360 US: 31 Mar → 30 Jun should equal 0.25 per spec 3.2.3'
        );
    }

    // Spec Part 3.2.4: THIRTY/360 EU. Same dates. D1=31→30, D2=30 (unchanged, <31).
    // Result also 0.25.
    @IsTest
    static void testTHIRTY360EU_SpecExample() {
        GenericDayCountCalculator calc = new GenericDayCountCalculator();
        Decimal fraction = calc.getDayCountFraction(
            Date.newInstance(2026, 3, 31),
            Date.newInstance(2026, 6, 30),
            'THIRTY_360_EU'
        );
        Assert.areEqual(
            0.25,
            fraction.setScale(6, RoundingMode.HALF_UP),
            'THIRTY/360 EU: 31 Mar → 30 Jun should equal 0.25 per spec 3.2.4'
        );
    }

    // Spec Part 3.2.5: ACT/ACT ISDA within same year — identical to ACT/365 for non-leap.
    @IsTest
    static void testISDA_SameYear_MatchesACT365() {
        GenericDayCountCalculator calc = new GenericDayCountCalculator();
        Decimal isda = calc.getDayCountFraction(
            Date.newInstance(2025, 3, 31),
            Date.newInstance(2025, 6, 30),
            'ACT_ACT_ISDA'
        );
        Decimal act365 = calc.getDayCountFraction(
            Date.newInstance(2025, 3, 31),
            Date.newInstance(2025, 6, 30),
            'ACT_365'
        );
        Assert.areEqual(
            act365.setScale(8, RoundingMode.HALF_UP),
            isda.setScale(8, RoundingMode.HALF_UP),
            'ACT/ACT ISDA same year (non-leap) should equal ACT/365'
        );
    }

    // Spec Part 3.2.5: ACT/ACT ISDA spanning non-leap (2023) → leap (2024) year boundary.
    // Period: Dec 1, 2023 → Feb 28, 2024.
    //   2023 segment: 31 days / 365 (2023 non-leap)
    //   2024 segment: 58 days / 366 (2024 leap year)
    //   Total fraction ≠ simple 89/365
    @IsTest
    static void testISDA_YearSplit_NonLeapIntoLeap() {
        GenericDayCountCalculator calc = new GenericDayCountCalculator();
        Decimal isda = calc.getDayCountFraction(
            Date.newInstance(2023, 12, 1),
            Date.newInstance(2024, 2, 28),
            'ACT_ACT_ISDA'
        );
        // Expected: 31/365 + 58/366
        Decimal expected = (31.0 / 365.0) + (58.0 / 366.0);
        Assert.areEqual(
            expected.setScale(8, RoundingMode.HALF_UP),
            isda.setScale(8, RoundingMode.HALF_UP),
            'ACT/ACT ISDA Dec 2023→Feb 2024 should split: 31/365 + 58/366'
        );
        // Also verify it differs from simple ACT/365 (89/365)
        Decimal simple = 89.0 / 365.0;
        Assert.areNotEqual(
            simple.setScale(8, RoundingMode.HALF_UP),
            isda.setScale(8, RoundingMode.HALF_UP),
            'ISDA year-split should differ from simple ACT/365 across leap-year boundary'
        );
    }

    // Spec Part 3.2.5: ACT/ACT ISDA spanning leap (2024) → non-leap (2025) year boundary.
    // Period: Dec 1, 2024 → Feb 28, 2025.
    //   2024 segment: 31 days / 366 (2024 leap)
    //   2025 segment: 58 days / 365 (2025 non-leap)
    @IsTest
    static void testISDA_YearSplit_LeapIntoNonLeap() {
        GenericDayCountCalculator calc = new GenericDayCountCalculator();
        Decimal isda = calc.getDayCountFraction(
            Date.newInstance(2024, 12, 1),
            Date.newInstance(2025, 2, 28),
            'ACT_ACT_ISDA'
        );
        Decimal expected = (31.0 / 366.0) + (58.0 / 365.0);
        Assert.areEqual(
            expected.setScale(8, RoundingMode.HALF_UP),
            isda.setScale(8, RoundingMode.HALF_UP),
            'ACT/ACT ISDA Dec 2024→Feb 2025 should split: 31/366 + 58/365'
        );
    }

    // Spec Part 3.4: full accrual example using FixedRateInterestCalculator.
    // Principal AUD 5,000,000. Rate 8.50%. Period 31 Mar to 30 Jun 2026. ACT/365.
    // Day count fraction = 91/365. Period interest = 5,000,000 × 0.085 × 91/365 = 105,958.90
    @IsTest
    static void testACT365_SpecPart34_DayCountFraction() {
        GenericDayCountCalculator calc = new GenericDayCountCalculator();
        Decimal fraction = calc.getDayCountFraction(
            Date.newInstance(2026, 3, 31),
            Date.newInstance(2026, 6, 30),
            'ACT_365'
        );
        // Verify the fraction drives the correct interest
        Decimal principal = 5000000;
        Decimal rate      = 8.5;
        Decimal interest  = (principal * (rate / 100) * fraction).setScale(2, RoundingMode.HALF_EVEN);
        Assert.areEqual(105958.90, interest, 'Spec Part 3.4: 5M × 8.5% × 91/365 = 105,958.90');
    }

    // Error path: unknown convention throws a descriptive exception.
    @IsTest
    static void testUnknownConventionThrows() {
        GenericDayCountCalculator calc = new GenericDayCountCalculator();
        Boolean threw = false;
        try {
            calc.getDayCountFraction(Date.today(), Date.today().addDays(30), 'NOT_A_CONVENTION');
        } catch (GenericDayCountCalculator.DayCountException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'Unknown convention should throw DayCountException');
    }
}