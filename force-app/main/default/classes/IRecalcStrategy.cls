/**
 * IRecalcStrategy
 * Implemented by each trigger-event strategy registered in Recalc_Scope__mdt.
 * RecalcCascadeService instantiates via Type.forName(Strategy_Class__c).
 * Adding a new cascade = add one MDT record, zero code change in the service.
 * Spec v3 Part 10.
 */
public interface IRecalcStrategy {
    /**
     * Execute recalculation for the triggering record.
     * @param recordId      Id of the record that fired the trigger event
     * @param correlationId Correlation Id for this cascade run
     */
    void execute(Id recordId, String correlationId);
}