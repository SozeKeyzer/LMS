/**
 * Governance-layer context passed to ICalculationStrategy implementations.
 * Distinct from the domain CalcContext (builder pattern) used by existing
 * engine calculators. This carries orchestration metadata, not domain fields.
 */
public class OrchestratorCalcContext {
    public Id parentRecordId;
    public String parentObjectApiName;
    public Map<String, SObject> relatedRecords;
    public String runMode; // Preview | Commit | Shadow
    public String calcDeveloperName;
    public String calcVersion;
}