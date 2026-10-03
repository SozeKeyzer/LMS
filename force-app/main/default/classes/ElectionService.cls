/**
 * ElectionService
 * Handles PIK borrower election workflow.
 * Locks elections, applies deadline defaults, validates Split amounts.
 * Called from Election__c trigger and RateDeferral_Screen flow.
 */
public class ElectionService {

    /**
     * Lock an election — called when the deadline passes or ops confirms.
     * Sets Election_Locked_Date, Election_Locked_By, Is_Immutable = true.
     */
    public static void lockElection(Id electionId) {
        Election__c el = [
            SELECT Id, Election_Type__c, Cash_Amount__c, PIK_Amount__c,
                   Payment_Schedule__c, Debt_Position__c
            FROM Election__c WHERE Id = :electionId
        ];

        TriggerContext.getInstance().bypassGuards = true;
        update new Election__c(
            Id                    = el.Id,
            Election_Locked_Date__c = DateTime.now(),
            Election_Locked_By__c   = UserInfo.getUserId(),
            Is_Immutable__c         = true
        );
        TriggerContext.getInstance().bypassGuards = false;

        AuditEventLogger.logManual('STATUS_CHANGED','Election__c',String.valueOf(electionId),
            'Election locked. Type: ' + el.Election_Type__c);
        AuditEventLogger.flush();
    }

    /**
     * Apply the default election when borrower misses the deadline.
     * Uses PIK_Default_Mode__c from the Debt_Position.
     */
    public static void applyDefault(Election__c el, Debt_Position__c dp) {
        String defaultType = 'Cash'; // fallback
        if (dp.PIK_Default_Mode__c == 'Auto_PIK') defaultType = 'PIK';

        TriggerContext.getInstance().bypassGuards = true;
        update new Election__c(
            Id                    = el.Id,
            Election_Type__c      = defaultType,
            Default_Applied__c    = true,
            Election_Locked_Date__c = DateTime.now(),
            Election_Locked_By__c   = UserInfo.getUserId(),
            Is_Immutable__c         = true
        );
        TriggerContext.getInstance().bypassGuards = false;

        AuditEventLogger.logEngine('STATUS_CHANGED','Election__c',String.valueOf(el.Id),
            'Default election applied: ' + defaultType + '. Borrower missed deadline.');
        AuditEventLogger.flush();
    }

    /** Validate a Split election — Cash + PIK must equal Interest_Due on the schedule. */
    public static Boolean validateSplitAmounts(Election__c el) {
        if (el.Election_Type__c != 'Split') return true;
        if (el.Payment_Schedule__c == null) return false;
        Payment_Schedule__c ps = [SELECT Id, Interest_Due__c FROM Payment_Schedule__c WHERE Id = :el.Payment_Schedule__c];
        Decimal total = (el.Cash_Amount__c != null ? el.Cash_Amount__c : 0)
                      + (el.PIK_Amount__c  != null ? el.PIK_Amount__c  : 0);
        return ps.Interest_Due__c != null && Math.abs(total - ps.Interest_Due__c) < 0.01;
    }
}