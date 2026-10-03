/**
 * ProjectionService
 * Manages Projection lifecycle: generate, promote, discard, expire.
 */
public class ProjectionService {

    public static Projection__c generateForAmendment(Id dpId, Id amendmentId, List<Object> projectedRows) {
        Projection__c proj = new Projection__c(
            Debt_Position__c    = dpId,
            Loan_Amendment__c   = amendmentId,
            Projection_Type__c  = 'Amendment_Preview',
            Generated_DateTime__c = DateTime.now(),
            Engine_Version__c   = CalculationEngineBase.ENGINE_VERSION,
            Projected_Rows__c   = JSON.serialize(projectedRows),
            Status__c           = 'Generated',
            Correlation_Id__c   = TriggerContext.getInstance().correlationId,
            Source__c           = 'System_Calculated'
        );
        insert proj;
        return proj;
    }

    public static void discard(Id projectionId) {
        TriggerContext.getInstance().bypassGuards = true;
        update new Projection__c(Id = projectionId, Status__c = 'Discarded', Discarded_DateTime__c = DateTime.now());
        TriggerContext.getInstance().bypassGuards = false;
    }
}