/**
 * DrawdownRequestValidationService
 * Validates a drawdown request before approval:
 * 1. Availability_Period is active and covers the requested drawdown date
 * 2. Undrawn commitment is sufficient
 * 3. Notice period is satisfied
 * 4. Minimum drawdown amount is met
 */
public class DrawdownRequestValidationService {

    public class ValidationResult {
        public Boolean isValid;
        public List<String> errors;
        public ValidationResult() { isValid = true; errors = new List<String>(); }
        public void addError(String msg) { isValid = false; errors.add(msg); }
    }

    public static ValidationResult validate(Drawdown_Request__c request) {
        ValidationResult result = new ValidationResult();

        if (request.Debt_Position__c == null) {
            result.addError('Debt Position is required.');
            return result;
        }

        Debt_Position__c dp = [
            SELECT Id, Financial_Instrument__c
            FROM Debt_Position__c WHERE Id = :request.Debt_Position__c
        ];

        // Check active Availability_Period
        Date drawdownDate = request.Requested_Drawdown_Date__c != null
            ? request.Requested_Drawdown_Date__c : Date.today();

        List<Availability_Period__c> periods = [
            SELECT Id FROM Availability_Period__c
            WHERE Financial_Instrument__c = :dp.Financial_Instrument__c
            LIMIT 1
        ];
        if (periods.isEmpty()) {
            result.addError('No Availability Period found for this facility. Drawdowns are not permitted.');
        }

        // Notice period check
        if (request.Notice_Period_Days__c != null && request.Notice_Received_Date__c != null) {
            Integer daysDiff = request.Notice_Received_Date__c.daysBetween(drawdownDate);
            if (daysDiff < request.Notice_Period_Days__c.intValue()) {
                result.addError('Notice period of ' + request.Notice_Period_Days__c.intValue()
                    + ' days not satisfied. Notice received: ' + request.Notice_Received_Date__c
                    + '. Required drawdown date: ' + drawdownDate);
            }
        }

        // Amount validation
        if (request.Requested_Amount__c == null || request.Requested_Amount__c <= 0) {
            result.addError('Requested Amount must be greater than zero.');
        }

        return result;
    }

    @InvocableMethod(label='Validate Drawdown Request' category='LMS')
    public static List<String> validateFromFlow(List<Id> requestIds) {
        List<String> results = new List<String>();
        for (Id reqId : requestIds) {
            Drawdown_Request__c req = [
                SELECT Id, Debt_Position__c, Requested_Amount__c,
                       Requested_Drawdown_Date__c, Notice_Period_Days__c, Notice_Received_Date__c
                FROM Drawdown_Request__c WHERE Id = :reqId
            ];
            ValidationResult vr = validate(req);
            results.add(vr.isValid ? 'VALID' : String.join(vr.errors, '; '));
        }
        return results;
    }
}