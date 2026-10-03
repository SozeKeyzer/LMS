/** RateFixingIngestionScheduler — morning scheduler, processes queued fixings. */
public class RateFixingIngestionScheduler implements Schedulable {
    public void execute(SchedulableContext sc) {
        List<Rate_Index_Fixing__c> pending = [
            SELECT Id, Rate_Index__c, Fixing_Date__c, Rate__c, External_Id__c
            FROM Rate_Index_Fixing__c
            WHERE Ingestion_Timestamp__c = null
        ];
        if (!pending.isEmpty()) RateFixingIngestionService.ingest(pending);
    }
}