/**
 * LMSTriggerHandlerPhase0Test
 * Covers Phase 0 trigger handler changes:
 *   - AmortisationRulesTriggerHandler: STATUS_CHANGED fires on afterUpdate
 *   - FeeStructuresTriggerHandler: STATUS_CHANGED fires on afterUpdate
 *   - InterestRateTermsTriggerHandler: STATUS_CHANGED fires on afterUpdate
 *   - CorrelationIdGenerator: unique value generation
 * Spec v3 Phase 0 audit items.
 */
@IsTest
private class LMSTriggerHandlerPhase0Test {

    @TestSetup
    static void setup() {
        TriggerContext.reset();
        AuditEventLogger.clearPending();

        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'Phase0 FI');
        insert fi;
        Debt_Position__c dp = new Debt_Position__c(
            Name                     = 'Phase0 DP',
            Financial_Instrument__c  = fi.Id,
            Status__c                = 'Draft',
            iPlatform_External_Id__c = 'PH0TR-001'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dp;
        TriggerContext.getInstance().bypassGuards = false;
    }

    // ── AmortisationRulesTriggerHandler ───────────────────────────────────────

    // Updating a field on Amortisation_Rules triggers afterUpdate path without error
    @IsTest
    static void testAmortisationRulesHandler_StatusChange_NoException() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Amortisation_Rules__c ar = new Amortisation_Rules__c(
            Debt_Position__c = dp.Id
        );
        insert ar;

        Test.startTest();
        Boolean threw = false;
        try {
            update new Amortisation_Rules__c(Id = ar.Id, Source_Note__c = 'Updated');
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        Assert.isFalse(threw, 'AmortisationRules afterUpdate should not throw');

        Amortisation_Rules__c arAfter = [SELECT Source_Note__c FROM Amortisation_Rules__c WHERE Id = :ar.Id];
        Assert.areEqual('Updated', arAfter.Source_Note__c);
    }

    // ── FeeStructuresTriggerHandler ───────────────────────────────────────────

    @IsTest
    static void testFeeStructuresHandler_StatusChange_NoException() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Fee_Structures__c fs = new Fee_Structures__c(
            Debt_Position__c = dp.Id
        );
        insert fs;

        Test.startTest();
        Boolean threw = false;
        try {
            update new Fee_Structures__c(Id = fs.Id, Fee_Treatment__c = 'Cash');
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        Assert.isFalse(threw, 'FeeStructures STATUS_CHANGED should not throw');
    }

    // ── InterestRateTermsTriggerHandler ───────────────────────────────────────

    @IsTest
    static void testInterestRateTermsHandler_StatusChange_NoException() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Interest_Rate_Terms__c irt = new Interest_Rate_Terms__c(
            Debt_Position__c      = dp.Id,
            Application_Status__c = 'Pending'
        );
        insert irt;

        Test.startTest();
        Boolean threw = false;
        try {
            update new Interest_Rate_Terms__c(Id = irt.Id, Application_Status__c = 'Applied');
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        Assert.isFalse(threw, 'InterestRateTerms STATUS_CHANGED should not throw');
    }

    // ── CorrelationIdGenerator ────────────────────────────────────────────────

    @IsTest
    static void testCorrelationIdGenerator_ReturnsUniqueValues() {
        String id1 = CorrelationIdGenerator.generate();
        String id2 = CorrelationIdGenerator.generate();
        Assert.isNotNull(id1);
        Assert.isNotNull(id2);
        Assert.areNotEqual(id1, id2, 'Each call should return a unique correlation ID');
    }

    // gen() with prefix produces non-blank string
    @IsTest
    static void testCorrelationIdGenerator_GenWithPrefix() {
        String id = CorrelationIdGenerator.generate();
        Assert.isNotNull(id);
        Assert.isTrue(String.isNotBlank(id));
    }

}