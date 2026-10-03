/** DailyAccrualScheduler — schedules DailyAccrualBatch each night at midnight. */
public class DailyAccrualScheduler implements Schedulable {
    public void execute(SchedulableContext sc) {
        Database.executeBatch(new DailyAccrualBatch(), 200);
    }
}