@isTest
private class LoanAmendmentHandlerTest {

    // ── Setup ─────────────────────────────────────────────────────────────────

    @TestSetup
    static void setup() {
        Account a = new Account(Name = 'Test Borrower');
        insert a;

        Financial_Instrument__c fi = new Financial_Instrument__c(
            Name            = 'Test Loan',
            Borrower__c     = a.Id,
            In_Amendment__c = true      // protected against UPDATE, safe to set on INSERT
        );
        insert fi;

        Debt_Position__c dp = new Debt_Position__c(
            Name                     = 'Test Tranche',
            Financial_Instrument__c  = fi.Id,
            In_Amendment__c          = true,
            iPlatform_External_Id__c = 'LNAMD-001'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dp;
        TriggerContext.getInstance().bypassGuards = false;

        TriggerContext.getInstance().bypassGuards = true;
        insert new Payment_Schedule__c(
            Debt_Position__c  = dp.Id,
            Status__c         = 'Projected',
            Period_Start__c   = Date.today(),
            Period_End__c     = Date.today().addMonths(3),
            Due_Date__c       = Date.today().addMonths(3),
            Principal_Due__c  = 0,
            Interest_Due__c   = 0,
            Fees_Due__c       = 0,
            Source__c         = 'System_Calculated',
            Engine_Version__c = CalculationEngineBase.ENGINE_VERSION,
            External_Id__c    = 'LA-PS-001'
        );
        TriggerContext.getInstance().bypassGuards = false;
    }

    // Helper: inserts a Loan_Amendment__c in Draft status.
    // Skips Status = Submitted to avoid VR_LA_03/04/05 (Amendment_Document,
    // Recalc_Projection, Impact_Summary are only required on → Submitted).
    static Loan_Amendment__c insertDraftLa(Id dpId) {
        Loan_Amendment__c la = new Loan_Amendment__c(
            Scope__c                   = 'Position',
            Debt_Position__c           = dpId,
            Proposed_Effective_Date__c = Date.today(),
            Amendment_Type__c          = 'Rate_Change'
        );
        insert la;
        return la;
    }

    // ── afterInsert ───────────────────────────────────────────────────────────

    @isTest
    static void insertLogsAuditEventWithoutException() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];

        Test.startTest();
        Boolean threw = false;
        try {
            insert new Loan_Amendment__c(
                Scope__c                   = 'Position',
                Debt_Position__c           = dp.Id,
                Proposed_Effective_Date__c = Date.today(),
                Amendment_Type__c          = 'Rate_Change'
            );
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(false, threw, 'Inserting a Draft amendment must not throw');
    }

    // ── beforeUpdate + afterUpdate — Status → Effective ───────────────────────
    // Transition path: Draft → Approved → Effective.
    // Draft → Approved skips Submitted, so VR_LA_03/04/05 never fire.
    // VR_LA_06 (forward-only) allows both transitions.

    @isTest
    static void statusTransitionToEffectiveSetsActualEffectiveDate() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Financial_Instrument__c fi = [SELECT Id FROM Financial_Instrument__c LIMIT 1];
        Loan_Amendment__c la = insertDraftLa(dp.Id);

        // Draft → Approved (no VRs fire)
        la.Status__c = 'Approved';
        update la;

        Test.startTest();
        // Approved → Effective — triggers beforeUpdate (sets Actual_Effective_Date, Before_State)
        //                      + afterUpdate (calls executeCommit)
        la.Status__c = 'Effective';
        update la;
        Test.stopTest();

        la = [SELECT Actual_Effective_Date__c FROM Loan_Amendment__c WHERE Id = :la.Id];
        System.assertEquals(Date.today(), la.Actual_Effective_Date__c,
            'Actual_Effective_Date__c must be set to today by beforeUpdate');
    }

    @isTest
    static void statusTransitionToEffectiveSetsBeforeState() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Loan_Amendment__c la = insertDraftLa(dp.Id);

        la.Status__c = 'Approved';
        update la;

        Test.startTest();
        la.Status__c = 'Effective';
        update la;
        Test.stopTest();

        la = [SELECT Before_State__c FROM Loan_Amendment__c WHERE Id = :la.Id];
        System.assertNotEquals(null, la.Before_State__c,
            'Before_State__c must be populated on → Effective');
        System.assertNotEquals('', la.Before_State__c,
            'Before_State__c must not be blank');
    }

    @isTest
    static void statusTransitionToEffectiveSetsAfterState() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Loan_Amendment__c la = insertDraftLa(dp.Id);

        la.Status__c = 'Approved';
        update la;

        Test.startTest();
        la.Status__c = 'Effective';
        update la;
        Test.stopTest();

        la = [SELECT After_State__c FROM Loan_Amendment__c WHERE Id = :la.Id];
        System.assertNotEquals(null, la.After_State__c,
            'After_State__c must be populated by executeCommit');
    }

    @isTest
    static void nonEffectiveTransitionDoesNotSetActualDate() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Loan_Amendment__c la = insertDraftLa(dp.Id);

        Test.startTest();
        // Draft → Approved: beforeUpdate fires but condition (→ Effective) is false
        la.Status__c = 'Approved';
        update la;
        Test.stopTest();

        la = [SELECT Actual_Effective_Date__c FROM Loan_Amendment__c WHERE Id = :la.Id];
        System.assertEquals(null, la.Actual_Effective_Date__c,
            'Actual_Effective_Date__c must remain null on non-Effective transitions');
    }
}