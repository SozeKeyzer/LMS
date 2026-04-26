/**
 * TriggerContext
 * Singleton per Apex transaction. Holds Correlation ID and engine mode.
 * NOTE: COMMIT is a reserved Apex keyword — engine mode uses APPLY instead.
 */
public class TriggerContext {

    public enum EngineMode { NONE, PREVIEW, APPLY }

    private static TriggerContext instance;

    public String     correlationId { get; private set; }
    public EngineMode mode          { get; private set; }
    public Boolean    bypassGuards  { get; set; }

    private TriggerContext() {
        this.correlationId = CorrelationIdGenerator.generate();
        this.mode          = EngineMode.NONE;
        this.bypassGuards  = false;
    }

    public static TriggerContext getInstance() {
        if (instance == null) {
            instance = new TriggerContext();
        }
        return instance;
    }

    public void setMode(EngineMode m) {
        this.mode = m;
    }

    public void refreshCorrelationId() {
        this.correlationId = CorrelationIdGenerator.generate();
    }

    @TestVisible
    public static void reset() {
        instance = null;
    }
}
