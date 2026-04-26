/**
 * EngineResult
 * Immutable-by-convention DTO returned by every strategy execution.
 * Strategies add records to commit/insert lists — the orchestrator decides
 * whether to actually DML them based on Preview vs Commit mode.
 */
public class EngineResult {
    public Boolean         success         { get; private set; }
    public Decimal         calculatedAmount{ get; private set; }
    public String          resultType      { get; private set; }
    public String          message         { get; private set; }
    public List<SObject>   recordsToInsert { get; private set; }
    public List<SObject>   recordsToUpdate { get; private set; }
    public Map<String,Object> metadata     { get; private set; }

    public EngineResult() {
        this.success          = true;
        this.recordsToInsert  = new List<SObject>();
        this.recordsToUpdate  = new List<SObject>();
        this.metadata         = new Map<String,Object>();
    }

    public void setAmount(Decimal amt)    { this.calculatedAmount = amt; }
    public void setResultType(String t)   { this.resultType = t; }
    public void addInsert(SObject record) { this.recordsToInsert.add(record); }
    public void addUpdate(SObject record) { this.recordsToUpdate.add(record); }
    public void putMeta(String k, Object v) { this.metadata.put(k, v); }

    public void addError(String msg) {
        this.success = false;
        this.message = msg;
    }
}
