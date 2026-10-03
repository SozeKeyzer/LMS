/**
 * MarginRatchetEvaluator
 * Spec v5 Part 2.9 + Rule R18.
 * Invoked when a Covenant_Test produces a new ratio result.
 * Evaluates which Pricing_Grid_Band applies and, if the band changed,
 * auto-creates a new Interest_Rate_Terms row with Rate_Segment_Type = Amended.
 *
 * Rule R18: Covenant-driven margin changes NEVER edit existing IRT rows.
 * A new IRT row is created with Rate_Segment_Type = Amended, Application_Status = Pending.
 * Prior IRT row moves to Application_Status = Superseded on Apply.
 */
public class MarginRatchetEvaluator {

    /**
     * Main entry point. Call when a Covenant_Test result changes.
     * @param dpId              Debt_Position being evaluated
     * @param covenantTestId    The Covenant_Test record that triggered this
     * @param testDate          Date of the covenant test
     * @param calculatedValue   The financial ratio result (e.g. 3.5 for 3.5x leverage)
     */
    public static void evaluate(Id dpId, Id covenantTestId, Date testDate, Decimal calculatedValue) {
        // Load the active Pricing_Grid for this DP
        Debt_Position__c dp = [SELECT Id, Pricing_Grid__c FROM Debt_Position__c WHERE Id = :dpId];
        if (dp.Pricing_Grid__c == null) return; // no pricing grid — no ratchet

        // Load all active bands ordered by Band_Order__c
        List<Pricing_Grid_Band__c> bands = [
            SELECT Id, Band_Order__c, Ratio_Lower_Bound__c, Ratio_Upper_Bound__c,
                   Margin__c, Band_Label__c
            FROM Pricing_Grid_Band__c
            WHERE Pricing_Grid__c = :dp.Pricing_Grid__c
            AND Is_Active__c = true
            ORDER BY Band_Order__c ASC
        ];
        if (bands.isEmpty()) return;

        // Find the applicable band for the calculated value
        // Spec Part 9.3: lower bound is null for the first/lowest band (no floor); upper bound is inclusive (<=)
        Pricing_Grid_Band__c applicableBand = null;
        for (Pricing_Grid_Band__c band : bands) {
            Boolean aboveFloor   = (band.Ratio_Lower_Bound__c == null || calculatedValue >= band.Ratio_Lower_Bound__c);
            Boolean belowCeiling = (band.Ratio_Upper_Bound__c == null || calculatedValue <= band.Ratio_Upper_Bound__c);
            if (aboveFloor && belowCeiling) {
                applicableBand = band;
                break;
            }
        }
        if (applicableBand == null) return; // value outside all bands — no action

        // Find the currently Applied IRT row for this DP
        List<Interest_Rate_Terms__c> currentIRTs = [
            SELECT Id, Spread__c, Application_Status__c, Rate_Segment_Type__c
            FROM Interest_Rate_Terms__c
            WHERE Debt_Position__c = :dpId
            AND Application_Status__c = 'Applied'
            ORDER BY Actual_Application_Date__c DESC
            LIMIT 1
        ];

        // Check if band changed — compare current spread to new band margin
        if (!currentIRTs.isEmpty()) {
            Decimal currentSpread = currentIRTs[0].Spread__c != null ? currentIRTs[0].Spread__c : 0;
            if (currentSpread == applicableBand.Margin__c) {
                // Same margin — no change needed
                AuditEventLogger.logEngine('RATE_APPLIED','Debt_Position__c',String.valueOf(dpId),
                    'MarginRatchetEvaluator: Covenant test result (' + calculatedValue + ') maps to same margin band — no IRT created.');
                AuditEventLogger.flush();
                return;
            }
        }

        // Rule R18: create new IRT row — NEVER edit existing
        String corrId = TriggerContext.getInstance().correlationId;
        Interest_Rate_Terms__c newIRT = new Interest_Rate_Terms__c(
            Debt_Position__c              = dpId,
            Rate_Segment_Type__c          = 'Amended Rate',
            Spread__c                     = applicableBand.Margin__c,
            Application_Rule__c           = 'Next_Period_Start',
            Application_Status__c         = 'Pending',
            Trigger_Condition_Met_Date__c = testDate,
            Trigger_Condition_Source__c   = String.valueOf(covenantTestId),
            Correlation_Id__c             = corrId,
            Source__c                     = 'System_Calculated',
            Engine_Version__c             = CalculationEngineBase.ENGINE_VERSION
        );

        TriggerContext.getInstance().bypassGuards = true;
        try {
            insert newIRT;
        } finally {
            TriggerContext.getInstance().bypassGuards = false;
        }

        AuditEventLogger.logEngine('RECORD_CREATED','Interest_Rate_Terms__c',
            String.valueOf(newIRT.Id),
            'MarginRatchetEvaluator: New margin band applied. Ratio: ' + calculatedValue
            + ' → Band: ' + (applicableBand.Band_Label__c != null ? applicableBand.Band_Label__c : String.valueOf(applicableBand.Id))
            + ' | New margin: ' + applicableBand.Margin__c + '%'
            + ' | Covenant_Test: ' + covenantTestId);
        AuditEventLogger.flush();
    }

    /**
     * Invocable entry point — call from Flow when Covenant_Test Status → Complete.
     */
    @InvocableMethod(label='Evaluate Margin Ratchet' category='LMS'
        description='Evaluates Pricing_Grid bands and auto-creates new IRT row if margin band has changed. Rule R18.')
    public static void evaluateFromFlow(List<RatchetRequest> requests) {
        for (RatchetRequest req : requests) {
            evaluate(req.debtPositionId, req.covenantTestId, req.testDate, req.calculatedValue);
        }
    }

    public class RatchetRequest {
        @InvocableVariable(required=true  label='Debt Position ID')    public Id      debtPositionId;
        @InvocableVariable(required=true  label='Covenant Test ID')    public Id      covenantTestId;
        @InvocableVariable(required=true  label='Test Date')           public Date    testDate;
        @InvocableVariable(required=true  label='Calculated Value')    public Decimal calculatedValue;
    }
}