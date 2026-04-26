/**
 * CalculationEngineBase
 * Abstract base for all engine orchestrators.
 * NOTE: COMMIT is a reserved Apex keyword — use APPLY for commit mode.
 */
public abstract class CalculationEngineBase {

    public static final String ENGINE_VERSION = '1.0.0';

    public enum Mode { PREVIEW, APPLY }

    protected Mode executionMode;

    public CalculationEngineBase(Mode m) {
        this.executionMode = m;
        TriggerContext.getInstance().setMode(
            m == Mode.PREVIEW
                ? TriggerContext.EngineMode.PREVIEW
                : TriggerContext.EngineMode.APPLY
        );
    }

    public Boolean isPreview() { return executionMode == Mode.PREVIEW; }
    public Boolean isApply()   { return executionMode == Mode.APPLY; }

    /**
     * Rule R10: only recalculate System_Calculated records.
     * @TestVisible so unit tests can call this protected method.
     */
    @TestVisible
    protected Boolean isEngineOwned(SObject record) {
        Object src = record.get('Source__c');
        return src == null || src == 'System_Calculated';
    }

    public abstract EngineResult execute(CalcContext ctx);

    protected void commitResult(EngineResult result) {
        if (!result.success || isPreview()) return;
        if (!result.recordsToInsert.isEmpty()) insert result.recordsToInsert;
        if (!result.recordsToUpdate.isEmpty()) update result.recordsToUpdate;
    }
}
