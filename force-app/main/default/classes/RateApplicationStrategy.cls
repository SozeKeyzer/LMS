/**
 * RateApplicationStrategy
 * IRecalcStrategy for Trigger_Field__c = 'Rate_Application_Apply'.
 * When a rate reset is applied, sets Rate_Finalisation_Status on schedule rows
 * to Rate_Applied and writes the locked rate from the applied IRT.
 * Spec v3 Part 10.1.
 *
 * recordId = Interest_Rate_Terms__c that has just been applied.
 */
public class RateApplicationStrategy implements IRecalcStrategy {

    public void execute(Id recordId, String correlationId) {
        Interest_Rate_Terms__c irt = [
            SELECT Id, Debt_Position__c, Applicable_Fixed_Rate__c, Spread__c,
                   Pricing_Basis__c, Contractual_Effective_From__c
            FROM Interest_Rate_Terms__c
            WHERE Id = :recordId
        ];

        if (irt.Debt_Position__c == null) return;

        // Update schedule rows from the IRT effective date forward
        List<Payment_Schedule__c> rows = [
            SELECT Id, Rate_Finalisation_Status__c, Placeholder_Base_Rate__c, Placeholder_Spread__c
            FROM Payment_Schedule__c
            WHERE Debt_Position__c = :irt.Debt_Position__c
              AND Status__c IN ('Projected', 'Due')
              AND Rate_Finalisation_Status__c IN ('Projected_Rate', 'Not_Finalised')
              AND Period_Start__c >= :irt.Contractual_Effective_From__c
        ];

        if (rows.isEmpty()) return;

        TriggerContext.getInstance().bypassGuards = true;
        try {
            for (Payment_Schedule__c ps : rows) {
                ps.Rate_Finalisation_Status__c = 'Rate_Applied';
                if (irt.Pricing_Basis__c == 'Fixed') {
                    ps.Placeholder_Base_Rate__c = irt.Applicable_Fixed_Rate__c;
                    ps.Placeholder_Spread__c    = 0;
                } else {
                    ps.Placeholder_Spread__c    = irt.Spread__c != null ? irt.Spread__c : 0;
                }
            }
            update rows;
        } finally {
            TriggerContext.getInstance().bypassGuards = false;
        }

        AuditEventLogger.logEngine(
            'RATE_APPLIED', 'Interest_Rate_Terms__c', String.valueOf(recordId),
            rows.size() + ' schedule row(s) updated to Rate_Applied. correlationId=' + correlationId
        );
        AuditEventLogger.flush();
    }
}