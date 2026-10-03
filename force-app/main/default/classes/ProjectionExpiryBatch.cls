/** ProjectionExpiryBatch — weekly. Discards un-promoted Projections older than 90 days. */
public class ProjectionExpiryBatch implements Database.Batchable<SObject> {
    public Database.QueryLocator start(Database.BatchableContext bc) {
        Date cutoff = Date.today().addDays(-90);
        return Database.getQueryLocator([
            SELECT Id FROM Projection__c
            WHERE Status__c IN ('Generated','Reviewed')
            AND Generated_DateTime__c < :cutoff
        ]);
    }
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<Projection__c> toUpdate = new List<Projection__c>();
        for (SObject s : scope) {
            toUpdate.add(new Projection__c(Id = s.Id, Status__c = 'Expired',
                Discarded_DateTime__c = DateTime.now()));
        }
        TriggerContext.getInstance().bypassGuards = true;
        if (!toUpdate.isEmpty()) update toUpdate;
        TriggerContext.getInstance().bypassGuards = false;
    }
    public void finish(Database.BatchableContext bc) {}
}