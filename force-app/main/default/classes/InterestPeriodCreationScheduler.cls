/**
 * InterestPeriodCreationScheduler
 * Schedules InterestPeriodCreationBatch to run each business day at T-2 before period resets.
 *
 * Recommended cron: '0 0 5 * * ?' (05:00 daily)
 * Must run BEFORE RateFixingIngestionScheduler. The batch creates Pending periods with null
 * rates. The fixing ingestion (which runs post-AFMA publication ~10:30) then locks the rate.
 *
 * Registration (run once in Execute Anonymous):
 *   System.schedule('Interest Period Creation', '0 0 5 * * ?', new InterestPeriodCreationScheduler());
 *
 * targetStart = today + 2 calendar days — aligns with the T-2 fixing convention.
 * ScheduleGenerationService adjusts period dates for weekends/business-day rules,
 * so Saturday/Sunday targetStart values will simply produce no Payment_Schedule match
 * and the batch skips all DPs gracefully.
 */
public class InterestPeriodCreationScheduler implements Schedulable {
    public void execute(SchedulableContext sc) {
        Date targetStart = Date.today().addDays(2);
        Database.executeBatch(new InterestPeriodCreationBatch(targetStart), 50);
    }
}