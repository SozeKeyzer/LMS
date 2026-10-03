/**
 * PIKCapitalisationService
 * Triggered at period end when PIK accruals exist.
 * Creates PIK_Capitalisation_Event__c, marks Payment_Schedule as Settled_PIK,
 * and creates a new Amortisation_Rules segment with the uplifted principal.
 */
public class PIKCapitalisationService {

    public static void capitalise(Id debtPositionId, Id interestPeriodId) {
        // Get PIK accruals for this period
        AggregateResult[] pikTotals = [
            SELECT SUM(Effective_Value__c) total
            FROM Accrual_Daily__c
            WHERE Debt_Position__c = :debtPositionId
            AND Interest_Period__c = :interestPeriodId
            AND Is_PIK__c = true
            AND Status__c = 'Accrued'
        ];

        if (pikTotals.isEmpty()) return;
        Decimal pikAmount = (Decimal)(pikTotals[0].get('total') != null ? pikTotals[0].get('total') : 0);
        if (pikAmount <= 0) return;

        Debt_Position__c dp = [SELECT Id, Outstanding_Balance__c, Total_PIK_Capitalised__c FROM Debt_Position__c WHERE Id = :debtPositionId];
        Decimal prePrincipal = dp.Outstanding_Balance__c != null ? dp.Outstanding_Balance__c : 0;
        Decimal postPrincipal = prePrincipal + pikAmount;

        Interest_Period__c ip = [SELECT Id, Period_Start__c, Period_End__c FROM Interest_Period__c WHERE Id = :interestPeriodId];

        // Find triggering schedule
        List<Payment_Schedule__c> schedules = [
            SELECT Id FROM Payment_Schedule__c
            WHERE Debt_Position__c = :debtPositionId
            AND Period_Start__c = :ip.Period_Start__c
            AND Status__c IN ('Due','Overdue','Projected')
            LIMIT 1
        ];

        String corrId = TriggerContext.getInstance().correlationId;

        // Create capitalisation event
        PIK_Capitalisation_Event__c capEvent = new PIK_Capitalisation_Event__c(
            Debt_Position__c                = debtPositionId,
            Capitalisation_Date__c          = Date.today(),
            PIK_Amount__c                   = pikAmount,
            Pre_Capitalisation_Principal__c  = prePrincipal,
            Post_Capitalisation_Principal__c = postPrincipal,
            Source_Accrual_Period_Start__c  = ip.Period_Start__c,
            Source_Accrual_Period_End__c    = ip.Period_End__c,
            Triggering_Schedule__c          = schedules.isEmpty() ? null : schedules[0].Id,
            Is_Immutable__c                 = true,
            Correlation_Id__c               = corrId,
            Source__c                       = 'System_Calculated',
            Engine_Version__c               = CalculationEngineBase.ENGINE_VERSION,
            External_Id__c                  = debtPositionId + '-' + Date.today().format()
        );

        TriggerContext.getInstance().bypassGuards = true;
        insert capEvent;

        // Mark PIK accruals as Capitalised
        List<Accrual_Daily__c> pikAccruals = [
            SELECT Id FROM Accrual_Daily__c
            WHERE Debt_Position__c = :debtPositionId
            AND Interest_Period__c = :interestPeriodId
            AND Is_PIK__c = true AND Status__c = 'Accrued'
        ];
        for (Accrual_Daily__c ad : pikAccruals) ad.Status__c = 'Capitalised';
        if (!pikAccruals.isEmpty()) update pikAccruals;

        // Mark schedule as Settled_PIK
        if (!schedules.isEmpty()) {
            update new Payment_Schedule__c(Id = schedules[0].Id, Status__c = 'Settled_PIK', Is_Immutable__c = true);
        }

        // Increment Total_PIK_Capitalised__c — Outstanding_Balance__c formula picks this up for reamortisation
        Decimal newTotalPIK = (dp.Total_PIK_Capitalised__c != null ? dp.Total_PIK_Capitalised__c : 0) + pikAmount;
        update new Debt_Position__c(Id = debtPositionId, Total_PIK_Capitalised__c = newTotalPIK);
        TriggerContext.getInstance().bypassGuards = false;

        // Re-amortise future schedule rows — Outstanding_Balance__c now reflects updated Total_PIK_Capitalised__c
        ScheduleReamortisationService.reamortiseAfterEvent(debtPositionId, ip.Period_End__c, corrId);

        AuditEventLogger.logEngine('ACCRUAL_POSTED','PIK_Capitalisation_Event__c',
            String.valueOf(capEvent.Id),
            'PIK capitalised: ' + pikAmount + '. Principal: ' + prePrincipal + ' -> ' + postPrincipal);
        AuditEventLogger.flush();
    }
}