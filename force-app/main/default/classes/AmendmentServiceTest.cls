@isTest
private class AmendmentServiceTest {

    // ── Shared test data ──────────────────────────────────────────────────────

    @TestSetup
    static void setup() {
        Account a = new Account(Name = 'Test Borrower');
        insert a;

        // In_Amendment__c is protected against direct UPDATE via ProtectedFieldGuard,
        // but INSERT is not guarded — set the flag here so tests start in the right state.
        Financial_Instrument__c fi = new Financial_Instrument__c(
            Name          = 'Test Loan',
            Borrower__c   = a.Id,
            In_Amendment__c = true
        );
        insert fi;

        Debt_Position__c dp = new Debt_Position__c(
            Name                      = 'Test Tranche',
            Financial_Instrument__c   = fi.Id,
            In_Amendment__c           = true,
            iPlatform_External_Id__c  = 'AMEND-001'
        );
        insert dp;

        // One PS row in scope (today forward) and one outside scope (yesterday)
        TriggerContext.getInstance().bypassGuards = true;
        insert new List<Payment_Schedule__c>{
            new Payment_Schedule__c(
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
                External_Id__c    = 'AMEND-PS-001'
            ),
            new Payment_Schedule__c(
                Debt_Position__c  = dp.Id,
                Status__c         = 'Projected',
                Period_Start__c   = Date.today().addDays(-1),   // before effective date — must NOT be superseded
                Period_End__c     = Date.today().addMonths(3).addDays(-1),
                Due_Date__c       = Date.today().addMonths(3).addDays(-1),
                Principal_Due__c  = 0,
                Interest_Due__c   = 0,
                Fees_Due__c       = 0,
                Source__c         = 'System_Calculated',
                Engine_Version__c = CalculationEngineBase.ENGINE_VERSION,
                External_Id__c    = 'AMEND-PS-002'
            )
        };
        TriggerContext.getInstance().bypassGuards = false;
    }

    // Helper: builds an in-memory LA record (no DML) for direct service method calls.
    // Using in-memory records avoids VR complexity when we only need to test the service logic.
    static Loan_Amendment__c buildLa(
        Id dpId, Id fiId, String scope, String amendmentType, Boolean insertLa
    ) {
        Loan_Amendment__c la = new Loan_Amendment__c(
            Scope__c                 = scope,
            Debt_Position__c         = (scope == 'Position') ? dpId : null,
            Financial_Instrument__c  = (scope == 'Facility') ? fiId : null,
            Proposed_Effective_Date__c = Date.today(),
            Amendment_Type__c        = amendmentType,
            Actual_Effective_Date__c = Date.today()
        );
        if (insertLa) insert la;
        return la;
    }

    // ── captureBeforeState ────────────────────────────────────────────────────

    @isTest
    static void captureBeforeStatePositionReturnsJson() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Financial_Instrument__c fi = [SELECT Id FROM Financial_Instrument__c LIMIT 1];
        Loan_Amendment__c la = buildLa(dp.Id, fi.Id, 'Position', 'Rate_Change', false);

        Test.startTest();
        String json = AmendmentService.captureBeforeState(la);
        Test.stopTest();

        System.assertNotEquals(null,   json, 'Before state JSON must not be null');
        System.assertNotEquals('',     json, 'Before state JSON must not be blank');
        System.assert(json.contains('"scope"'), 'JSON must contain scope key');
        System.assert(json.contains('"Position"'), 'JSON must contain scope value');
    }

    @isTest
    static void captureBeforeStateFacilityReturnsJson() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Financial_Instrument__c fi = [SELECT Id FROM Financial_Instrument__c LIMIT 1];
        Loan_Amendment__c la = buildLa(dp.Id, fi.Id, 'Facility', 'Rate_Change', false);

        Test.startTest();
        String json = AmendmentService.captureBeforeState(la);
        Test.stopTest();

        System.assertNotEquals(null, json, 'Before state JSON must not be null');
        System.assert(json.contains('"Facility"'), 'JSON must contain Facility scope value');
    }

    @isTest
    static void captureBeforeStateEmptyWhenNoScope() {
        Loan_Amendment__c la = new Loan_Amendment__c();   // no Scope, no DP, no FI

        Test.startTest();
        String json = AmendmentService.captureBeforeState(la);
        Test.stopTest();

        // resolveDPs returns empty list → debtPositions array is empty
        System.assertNotEquals(null, json, 'JSON must not be null even with no scope');
    }

    // ── executeCommit — Position scope ────────────────────────────────────────

    @isTest
    static void executeCommitSupersedesOpenPsRowsFromEffectiveDate() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Financial_Instrument__c fi = [SELECT Id FROM Financial_Instrument__c LIMIT 1];
        Loan_Amendment__c la = buildLa(dp.Id, fi.Id, 'Position', 'Rate_Change', true);

        Test.startTest();
        AmendmentService.executeCommit(la);
        Test.stopTest();

        List<Payment_Schedule__c> superseded = [
            SELECT Id, Status__c
            FROM Payment_Schedule__c
            WHERE Debt_Position__c = :dp.Id AND Status__c = 'Superseded'
        ];
        // Only the row with Period_Start = today (>= Actual_Effective_Date = today) is superseded
        System.assertEquals(1, superseded.size(), 'Exactly one PS row must be superseded');
    }

    @isTest
    static void executeCommitDoesNotSupersedeRowsBeforeEffectiveDate() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Financial_Instrument__c fi = [SELECT Id FROM Financial_Instrument__c LIMIT 1];
        Loan_Amendment__c la = buildLa(dp.Id, fi.Id, 'Position', 'Rate_Change', true);

        Test.startTest();
        AmendmentService.executeCommit(la);
        Test.stopTest();

        List<Payment_Schedule__c> stillProjected = [
            SELECT Id FROM Payment_Schedule__c
            WHERE Debt_Position__c = :dp.Id
              AND Status__c = 'Projected'
              AND Period_Start__c < :Date.today()
        ];
        System.assertEquals(1, stillProjected.size(), 'PS row before effective date must stay Projected');
    }

    @isTest
    static void executeCommitClearsDpInAmendmentFlag() {
        Debt_Position__c dp = [SELECT Id, In_Amendment__c FROM Debt_Position__c LIMIT 1];
        Financial_Instrument__c fi = [SELECT Id FROM Financial_Instrument__c LIMIT 1];
        System.assertEquals(true, dp.In_Amendment__c, 'Pre-condition: DP must be In Amendment');
        Loan_Amendment__c la = buildLa(dp.Id, fi.Id, 'Position', 'Rate_Change', true);

        Test.startTest();
        AmendmentService.executeCommit(la);
        Test.stopTest();

        dp = [SELECT In_Amendment__c FROM Debt_Position__c WHERE Id = :dp.Id];
        System.assertEquals(false, dp.In_Amendment__c, 'DP.In_Amendment__c must be cleared after commit');
    }

    @isTest
    static void executeCommitClearsFiInAmendmentFlagWhenNoDpsRemain() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Financial_Instrument__c fi = [SELECT Id, In_Amendment__c FROM Financial_Instrument__c LIMIT 1];
        System.assertEquals(true, fi.In_Amendment__c, 'Pre-condition: FI must be In Amendment');
        Loan_Amendment__c la = buildLa(dp.Id, fi.Id, 'Position', 'Rate_Change', true);

        Test.startTest();
        AmendmentService.executeCommit(la);
        Test.stopTest();

        fi = [SELECT In_Amendment__c FROM Financial_Instrument__c WHERE Id = :fi.Id];
        System.assertEquals(false, fi.In_Amendment__c, 'FI.In_Amendment__c must be cleared when no DPs remain');
    }

    @isTest
    static void executeCommitDoesNotClearFiWhenOtherDpsStillInAmendment() {
        Debt_Position__c dp1 = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Financial_Instrument__c fi = [SELECT Id FROM Financial_Instrument__c LIMIT 1];

        // Insert a second DP in amendment — FI flag must stay true after committing only dp1
        Debt_Position__c dp2 = new Debt_Position__c(
            Name                     = 'Second Tranche',
            Financial_Instrument__c  = fi.Id,
            In_Amendment__c          = true,
            iPlatform_External_Id__c = 'AMND-DP2A'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dp2;
        TriggerContext.getInstance().bypassGuards = false;

        Loan_Amendment__c la = buildLa(dp1.Id, fi.Id, 'Position', 'Rate_Change', true);

        Test.startTest();
        AmendmentService.executeCommit(la);
        Test.stopTest();

        fi = [SELECT In_Amendment__c FROM Financial_Instrument__c WHERE Id = :fi.Id];
        System.assertEquals(true, fi.In_Amendment__c,
            'FI.In_Amendment__c must stay true while dp2 is still In Amendment');
    }

    @isTest
    static void executeCommitSetsAfterState() {
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Financial_Instrument__c fi = [SELECT Id FROM Financial_Instrument__c LIMIT 1];
        Loan_Amendment__c la = buildLa(dp.Id, fi.Id, 'Position', 'Rate_Change', true);

        Test.startTest();
        AmendmentService.executeCommit(la);
        Test.stopTest();

        la = [SELECT After_State__c FROM Loan_Amendment__c WHERE Id = :la.Id];
        System.assertNotEquals(null,  la.After_State__c, 'After_State__c must be populated');
        System.assertNotEquals('',    la.After_State__c, 'After_State__c must not be blank');
    }

    @isTest
    static void executeCommitNoCrashWhenNoPsRows() {
        // Delete all PS rows — commit must handle empty PS gracefully
        delete [SELECT Id FROM Payment_Schedule__c];

        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Financial_Instrument__c fi = [SELECT Id FROM Financial_Instrument__c LIMIT 1];
        Loan_Amendment__c la = buildLa(dp.Id, fi.Id, 'Position', 'Rate_Change', true);

        Test.startTest();
        Boolean threw = false;
        try {
            AmendmentService.executeCommit(la);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(false, threw, 'executeCommit must not throw when there are no PS rows');
    }

    @isTest
    static void executeCommitNoCrashWhenDpNotFound() {
        // Create a temporary DP with no PS rows so it can be deleted freely.
        // PS.Debt_Position__c has deleteConstraint=Restrict — a DP with PS rows cannot be deleted.
        Financial_Instrument__c fi = [SELECT Id FROM Financial_Instrument__c LIMIT 1];
        Debt_Position__c tempDp = new Debt_Position__c(
            Name                     = 'Temp Tranche',
            Financial_Instrument__c  = fi.Id,
            iPlatform_External_Id__c = 'AMND-TMP1'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert tempDp;
        TriggerContext.getInstance().bypassGuards = false;

        Loan_Amendment__c la = new Loan_Amendment__c(
            Scope__c                   = 'Position',
            Debt_Position__c           = tempDp.Id,
            Proposed_Effective_Date__c = Date.today(),
            Amendment_Type__c          = 'Rate_Change',
            Actual_Effective_Date__c   = Date.today()
        );
        insert la;

        // Delete tempDp — succeeds because no PS rows are attached.
        // LA.Debt_Position__c becomes null in DB (SetNull default), but the
        // in-memory la object still holds tempDp.Id so resolveDPs queries a
        // now-missing record and returns an empty list.
        delete tempDp;

        Test.startTest();
        Boolean threw = false;
        try {
            AmendmentService.executeCommit(la);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(false, threw, 'executeCommit must not throw when DP is not found');
    }

    // ── executeCommit — Facility scope ────────────────────────────────────────

    @isTest
    static void executeCommitFacilityScopeSupersedesdAllDps() {
        Financial_Instrument__c fi = [SELECT Id FROM Financial_Instrument__c LIMIT 1];
        Debt_Position__c dp1 = [SELECT Id FROM Debt_Position__c LIMIT 1];

        Debt_Position__c dp2 = new Debt_Position__c(
            Name                     = 'Second Tranche',
            Financial_Instrument__c  = fi.Id,
            In_Amendment__c          = true,
            iPlatform_External_Id__c = 'AMND-DP2B'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dp2;
        TriggerContext.getInstance().bypassGuards = false;

        // PS rows for dp2
        TriggerContext.getInstance().bypassGuards = true;
        insert new Payment_Schedule__c(
            Debt_Position__c  = dp2.Id,
            Status__c         = 'Projected',
            Period_Start__c   = Date.today(),
            Period_End__c     = Date.today().addMonths(3),
            Due_Date__c       = Date.today().addMonths(3),
            Principal_Due__c  = 0,
            Interest_Due__c   = 0,
            Fees_Due__c       = 0,
            Source__c         = 'System_Calculated',
            Engine_Version__c = CalculationEngineBase.ENGINE_VERSION,
            External_Id__c    = 'AMEND-DP2-PS-001'
        );
        TriggerContext.getInstance().bypassGuards = false;

        Loan_Amendment__c la = buildLa(dp1.Id, fi.Id, 'Facility', 'Rate_Change', true);

        Test.startTest();
        AmendmentService.executeCommit(la);
        Test.stopTest();

        // Both DPs must be cleared
        List<Debt_Position__c> stillInAmendment = [
            SELECT Id FROM Debt_Position__c
            WHERE Financial_Instrument__c = :fi.Id AND In_Amendment__c = true
        ];
        System.assertEquals(0, stillInAmendment.size(), 'All DPs must be cleared after Facility commit');

        // PS rows for both DPs on or after effective date must be superseded
        List<Payment_Schedule__c> superseded = [
            SELECT Id FROM Payment_Schedule__c
            WHERE Debt_Position__c IN (:dp1.Id, :dp2.Id)
              AND Status__c = 'Superseded'
        ];
        System.assertEquals(2, superseded.size(), 'Both DPs must have their PS rows superseded');
    }

    @isTest
    static void executeCommitFacilityScopeClearsFiFlag() {
        Financial_Instrument__c fi = [SELECT Id FROM Financial_Instrument__c LIMIT 1];
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Loan_Amendment__c la = buildLa(dp.Id, fi.Id, 'Facility', 'Rate_Change', true);

        Test.startTest();
        AmendmentService.executeCommit(la);
        Test.stopTest();

        fi = [SELECT In_Amendment__c FROM Financial_Instrument__c WHERE Id = :fi.Id];
        System.assertEquals(false, fi.In_Amendment__c, 'FI flag must be cleared after Facility commit');
    }

    // ── generatePreview ───────────────────────────────────────────────────────

    @isTest
    static void generatePreview_NullId_ThrowsAuraHandledException() {
        Boolean threw = false;
        Test.startTest();
        try {
            AmendmentService.generatePreview(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw, 'null amendmentId must throw AuraHandledException');
    }

    @isTest
    static void generatePreview_NonExistentId_ReturnsNull() {
        // Build a fake Id that doesn't exist in the org
        Id fakeId = '001000000000000AAA';
        Test.startTest();
        Id result = AmendmentService.generatePreview(fakeId);
        Test.stopTest();
        System.assertEquals(null, result, 'Non-existent amendment Id must return null');
    }

    @isTest
    static void generatePreview_NoIRT_ThrowsAuraHandledException() {
        // DP exists (from setup) but no IRT is set on it — should throw
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Financial_Instrument__c fi = [SELECT Id FROM Financial_Instrument__c LIMIT 1];

        Loan_Amendment__c la = buildLa(dp.Id, fi.Id, 'Position', 'Rate_Change', true);

        // Delete all IRTs for this DP so the service can't find one
        delete [SELECT Id FROM Interest_Rate_Terms__c WHERE Debt_Position__c = :dp.Id];

        Test.startTest();
        Boolean threw = false;
        try {
            AmendmentService.generatePreview(la.Id);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw, 'Missing IRT must throw AuraHandledException');
    }

    @isTest
    static void generatePreview_NoFutureScheduleRows_ThrowsAuraHandledException() {
        // Delete PS rows so there are none on or after proposed effective date
        Debt_Position__c dp = [SELECT Id FROM Debt_Position__c LIMIT 1];
        Financial_Instrument__c fi = [SELECT Id FROM Financial_Instrument__c LIMIT 1];

        delete [SELECT Id FROM Payment_Schedule__c];

        // Add an Applied IRT (required before generatePreview can reach the PS check)
        TriggerContext.getInstance().bypassGuards = true;
        insert new Interest_Rate_Terms__c(
            Debt_Position__c           = dp.Id,
            Pricing_Basis__c           = 'Fixed',
            Applicable_Fixed_Rate__c   = 8.0,
            Application_Status__c      = 'Applied',
            Actual_Application_Date__c = Date.today().addDays(-1)
        );
        // Also ensure DP has a non-zero principal so we pass that check
        update new Debt_Position__c(Id = dp.Id, Position_Notional__c = 5000000);
        TriggerContext.getInstance().bypassGuards = false;

        Loan_Amendment__c la = buildLa(dp.Id, fi.Id, 'Position', 'Rate_Change', true);

        Test.startTest();
        Boolean threw = false;
        try {
            AmendmentService.generatePreview(la.Id);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw, 'No future PS rows must throw AuraHandledException');
    }

    @isTest
    static void generatePreview_ValidData_ReturnsProjectionId() {
        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'Preview FI');
        insert fi;

        Debt_Position__c dp = new Debt_Position__c(
            Name                      = 'Preview Tranche',
            Financial_Instrument__c   = fi.Id,
            Status__c                 = 'Active',
            Day_Count_Convention__c   = 'ACT_365',
            Position_Notional__c      = 5000000,
            In_Amendment__c           = true,
            iPlatform_External_Id__c  = 'PRVW-001'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dp;

        // Applied IRT — fallback path (no Pending Amendment IRT)
        insert new Interest_Rate_Terms__c(
            Debt_Position__c           = dp.Id,
            Application_Status__c      = 'Applied',
            Pricing_Basis__c           = 'Fixed',
            Applicable_Fixed_Rate__c   = 8.0,
            Actual_Application_Date__c = Date.today().addDays(-1)
        );

        // Future PS row starting today
        Date futureDate = Date.today();
        insert new Payment_Schedule__c(
            Debt_Position__c  = dp.Id,
            Status__c         = 'Projected',
            Period_Start__c   = futureDate,
            Period_End__c     = futureDate.addMonths(3),
            Due_Date__c       = futureDate.addMonths(3),
            Principal_Due__c  = 500000,
            Interest_Due__c   = 0,
            Fees_Due__c       = 0,
            Source__c         = 'System_Calculated',
            Engine_Version__c = CalculationEngineBase.ENGINE_VERSION,
            External_Id__c    = 'PRVW-PS-001'
        );
        TriggerContext.getInstance().bypassGuards = false;

        Loan_Amendment__c la = new Loan_Amendment__c(
            Debt_Position__c           = dp.Id,
            Scope__c                   = 'Position',
            Amendment_Type__c          = 'Rate_Change',
            Proposed_Effective_Date__c = futureDate
        );
        insert la;

        Test.startTest();
        Id projId = AmendmentService.generatePreview(la.Id);
        Test.stopTest();

        System.assertNotEquals(null, projId, 'generatePreview must return a non-null Projection Id');

        Projection__c proj = [SELECT Status__c, Debt_Position__c FROM Projection__c WHERE Id = :projId];
        System.assertEquals('Generated', proj.Status__c, 'Projection must have Status=Generated');
        System.assertEquals(dp.Id, proj.Debt_Position__c, 'Projection must link to the DP');

        // Amendment must be linked back to the projection
        la = [SELECT Recalc_Projection__c FROM Loan_Amendment__c WHERE Id = :la.Id];
        System.assertEquals(projId, la.Recalc_Projection__c, 'LA.Recalc_Projection__c must be set');
    }

    @isTest
    static void generatePreview_FacilityScope_ResolvesFirstInAmendmentDP() {
        Financial_Instrument__c fi = new Financial_Instrument__c(Name = 'FacPrev FI', In_Amendment__c = true);
        insert fi;

        Debt_Position__c dp = new Debt_Position__c(
            Name                      = 'FacPrev DP',
            Financial_Instrument__c   = fi.Id,
            Status__c                 = 'Active',
            Day_Count_Convention__c   = 'ACT_365',
            Position_Notional__c      = 2000000,
            In_Amendment__c           = true,
            iPlatform_External_Id__c  = 'PRVWFAC01'
        );
        TriggerContext.getInstance().bypassGuards = true;
        insert dp;

        insert new Interest_Rate_Terms__c(
            Debt_Position__c           = dp.Id,
            Application_Status__c      = 'Applied',
            Pricing_Basis__c           = 'Fixed',
            Applicable_Fixed_Rate__c   = 7.5,
            Actual_Application_Date__c = Date.today().addDays(-1)
        );

        Date futureDate = Date.today();
        insert new Payment_Schedule__c(
            Debt_Position__c  = dp.Id,
            Status__c         = 'Projected',
            Period_Start__c   = futureDate,
            Period_End__c     = futureDate.addMonths(6),
            Due_Date__c       = futureDate.addMonths(6),
            Principal_Due__c  = 200000,
            Interest_Due__c   = 0,
            Fees_Due__c       = 0,
            Source__c         = 'System_Calculated',
            Engine_Version__c = CalculationEngineBase.ENGINE_VERSION,
            External_Id__c    = 'PRVW-FAC-PS-001'
        );
        TriggerContext.getInstance().bypassGuards = false;

        // Facility-scope LA — no Debt_Position__c set, only FI
        Loan_Amendment__c la = new Loan_Amendment__c(
            Financial_Instrument__c    = fi.Id,
            Scope__c                   = 'Facility',
            Amendment_Type__c          = 'Rate_Change',
            Proposed_Effective_Date__c = futureDate
        );
        insert la;

        Test.startTest();
        Id projId = AmendmentService.generatePreview(la.Id);
        Test.stopTest();

        System.assertNotEquals(null, projId, 'Facility-scope generatePreview must return a Projection Id');
    }
}