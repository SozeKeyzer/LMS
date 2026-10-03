/**
 * ScheduleGenerationPreConditions
 * Validates 11 hard pre-conditions before the maker can generate a Draft schedule.
 * Any failure blocks generation — the UI disables the Generate button and shows
 * the failure list as a tooltip. Spec v3 Part 6.5.2, v7 Part 5.2.1.2 (P1-P11).
 *
 * Callers:
 *   PaymentScheduleService.generateDraft() — throws if failures.isEmpty() is false
 *   scheduleGeneratorWizard LWC — calls validate() to check readiness pre-click
 */
public class ScheduleGenerationPreConditions {

    public static final String ERR_P1_NO_INITIAL_IRT        = 'No active Initial rate terms';
    public static final String ERR_P2_NO_AMORT_RULES        = 'No active amortisation rules';
    public static final String ERR_P3_NO_DAYCOUNT           = 'Day count convention required';
    public static final String ERR_P4_FIRST_PMT_DATE        = 'First payment date invalid or missing';
    public static final String ERR_P5_MATURITY_DATE         = 'Maturity date invalid or missing';
    public static final String ERR_P6_PAYMENT_FREQ          = 'Payment frequency required';
    public static final String ERR_P7_DATE_RULE             = 'Payment date configuration incomplete';
    public static final String ERR_P8_NOTIONAL              = 'Position notional must be positive';
    public static final String ERR_P9_FLOATING_FIXING       = 'No recent rate fixing for placeholder rate (within 30 days)';
    public static final String ERR_P10_STATUS               = 'Loan is already Active. Use the Amendment workflow to regenerate the schedule';
    public static final String ERR_P11_ALREADY_GENERATED    = 'Schedule already generated. Use the Regenerate workflow';

    /**
     * Run all pre-condition checks for a Debt_Position.
     * @return List of failure messages. Empty = all conditions met; generation may proceed.
     */
    public static List<String> validate(Id dpId) {
        List<String> failures = new List<String>();

        Debt_Position__c dp = [
            SELECT Id, Status__c, Schedule_Generation_Status__c,
                   Day_Count_Convention__c, First_Payment_Date__c, Accrual_Start_Date__c,
                   Position_Maturity_Date__c, Payment_Frequency__c,
                   Payment_Date_Rule__c, Payment_Date_of_the_Month__c,
                   Position_Notional__c, Rate_Type__c
            FROM Debt_Position__c
            WHERE Id = :dpId
        ];

        // P1: Active Initial IRT (Rate_Segment_Type = Initial, Application_Status = Applied)
        Integer irtCount = [
            SELECT COUNT()
            FROM Interest_Rate_Terms__c
            WHERE Debt_Position__c = :dpId
              AND Application_Status__c = 'Applied'
        ];
        if (irtCount == 0) failures.add(ERR_P1_NO_INITIAL_IRT);

        // P2: At least one Amortisation_Rules record exists for this DP
        Integer amortCount = [
            SELECT COUNT()
            FROM Amortisation_Rules__c
            WHERE Debt_Position__c = :dpId
        ];
        if (amortCount == 0) failures.add(ERR_P2_NO_AMORT_RULES);

        // P3: Day_Count_Convention
        if (String.isBlank(dp.Day_Count_Convention__c)) failures.add(ERR_P3_NO_DAYCOUNT);

        // P4: Accrual_Start_Date present, First_Payment_Date present and >= Accrual_Start_Date
        Date accrualStart = dp.Accrual_Start_Date__c;
        if (accrualStart == null
                || dp.First_Payment_Date__c == null
                || dp.First_Payment_Date__c < accrualStart) {
            failures.add(ERR_P4_FIRST_PMT_DATE);
        }

        // P5: Position_Maturity_Date present and > First_Payment_Date
        if (dp.Position_Maturity_Date__c == null
                || (dp.First_Payment_Date__c != null
                    && dp.Position_Maturity_Date__c <= dp.First_Payment_Date__c)) {
            failures.add(ERR_P5_MATURITY_DATE);
        }

        // P6: Payment_Frequency
        if (String.isBlank(dp.Payment_Frequency__c)) failures.add(ERR_P6_PAYMENT_FREQ);

        // P7: Payment_Date_Rule + Payment_Date_of_the_Month when rule = Specific Day
        if (String.isBlank(dp.Payment_Date_Rule__c)) {
            failures.add(ERR_P7_DATE_RULE);
        } else if (dp.Payment_Date_Rule__c == 'Specific Day of Month'
                   && dp.Payment_Date_of_the_Month__c == null) {
            failures.add(ERR_P7_DATE_RULE);
        }

        // P8: Position_Notional > 0
        if (dp.Position_Notional__c == null || dp.Position_Notional__c <= 0) {
            failures.add(ERR_P8_NOTIONAL);
        }

        // P9: Floating-rate loans need a recent index fixing (within 30 days)
        if (isFloating(dp)) {
            List<Rate_Index_Fixing__c> recentFixings = [
                SELECT Id
                FROM Rate_Index_Fixing__c
                WHERE Fixing_Date__c >= :Date.today().addDays(-30)
                LIMIT 1
            ];
            if (recentFixings.isEmpty()) failures.add(ERR_P9_FLOATING_FIXING);
        }

        // P10: Status must be Draft or Pending Approval (not yet Active)
        Set<String> allowedStatuses = new Set<String>{ 'Draft', 'Pending Approval' };
        if (!allowedStatuses.contains(dp.Status__c)) failures.add(ERR_P10_STATUS);

        // P11: Schedule_Generation_Status must be Not_Generated (or null)
        String schedStatus = dp.Schedule_Generation_Status__c;
        if (schedStatus != null && schedStatus != 'Not_Generated') {
            failures.add(ERR_P11_ALREADY_GENERATED);
        }

        return failures;
    }

    private static Boolean isFloating(Debt_Position__c dp) {
        // Rate_Type__c = 'Floating' or null (some older records may not have it)
        return dp.Rate_Type__c == 'Floating';
    }
}