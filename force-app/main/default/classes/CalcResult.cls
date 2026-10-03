public class CalcResult {
    public Boolean success;
    public String errorMessage;
    public List<SObject> outputRows;
    public Map<String, Object> inputsSnapshot;
    public List<String> validationMessages;
    public List<String> invalidatesDownstream;

    public static CalcResult failed(String msg) {
        CalcResult r = new CalcResult();
        r.success = false;
        r.errorMessage = msg;
        r.outputRows = new List<SObject>();
        r.inputsSnapshot = new Map<String, Object>();
        r.validationMessages = new List<String>();
        r.invalidatesDownstream = new List<String>();
        return r;
    }

    public static CalcResult skipped(String msg) {
        CalcResult r = new CalcResult();
        r.success = false;
        r.errorMessage = msg;
        r.outputRows = new List<SObject>();
        r.inputsSnapshot = new Map<String, Object>();
        r.validationMessages = new List<String>();
        r.invalidatesDownstream = new List<String>();
        return r;
    }
}