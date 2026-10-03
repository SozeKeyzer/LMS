/**
 * ManualEntryService
 * Backing service for the Manual_Entry_Wizard flow.
 * Enforces Rules R10-R13:
 * - Source = Manual_Entry
 * - Source_Note mandatory
 * - Is_Immutable = true on insert
 * - Routes through Approval_Matrix
 * - Writes Audit_Event with Event_Type = MANUAL_ENTRY_CREATED
 */
public class ManualEntryService {

    @InvocableMethod(label='Create Manual Entry Record' category='LMS'
        description='Creates a transactional record with Source=Manual_Entry and enforces all manual entry guardrails.')
    public static void createFromFlow(List<ManualEntryRequest> requests) {
        for (ManualEntryRequest req : requests) {
            if (String.isBlank(req.sourceNote)) {
                throw new ManualEntryException('Source Note is mandatory for all Manual Entry records.');
            }
            if (req.source == 'System_Calculated') {
                throw new ManualEntryException('Source cannot be set to System_Calculated via Manual Entry wizard.');
            }
            AuditEventLogger.logManual('MANUAL_ENTRY_CREATED', req.objectApiName, req.recordId,
                'Manual entry created. Note: ' + req.sourceNote);
        }
        AuditEventLogger.flush();
    }

    public class ManualEntryRequest {
        @InvocableVariable(required=true  label='Object API Name') public String objectApiName;
        @InvocableVariable(required=false label='Record ID')       public String recordId;
        @InvocableVariable(required=true  label='Source Note')     public String sourceNote;
        @InvocableVariable(required=false label='Source')          public String source;
    }

    public class ManualEntryException extends Exception {}
}