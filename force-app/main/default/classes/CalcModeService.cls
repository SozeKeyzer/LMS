public with sharing class CalcModeService {

    public static void enterManualMode(Id recordId, String objectApiName,
                                        String reason, String explanation,
                                        Integer expectedDurationDays) {
        Calc_Mode_Change__c episode = new Calc_Mode_Change__c(
            Mode_From__c = 'Engine',
            Mode_To__c = 'Manual',
            Reason__c = reason,
            Explanation__c = explanation,
            Expected_Duration_Days__c = expectedDurationDays,
            Requested_By__c = UserInfo.getUserId(),
            Requested_At__c = Datetime.now(),
            Status__c = 'Pending_Approval'
        );
        if (objectApiName == 'Debt_Position__c') {
            episode.Debt_Position__c = recordId;
        } else if (objectApiName == 'Financial_Instrument__c') {
            episode.Financial_Instrument__c = recordId;
        }
        insert episode;
    }

    public static void activateManualMode(Id episodeId) {
        Calc_Mode_Change__c episode = [
            SELECT Id, Mode_To__c, Debt_Position__c, Financial_Instrument__c
            FROM Calc_Mode_Change__c WHERE Id = :episodeId
        ];
        episode.Status__c = 'Active';
        episode.Approved_By__c = UserInfo.getUserId();
        episode.Approved_At__c = Datetime.now();
        update episode;

        if (episode.Debt_Position__c != null) {
            update new Debt_Position__c(
                Id = episode.Debt_Position__c,
                Calc_Mode__c = episode.Mode_To__c,
                Calc_Mode_Since__c = Datetime.now(),
                Active_Mode_Change__c = episodeId
            );
        } else if (episode.Financial_Instrument__c != null) {
            update new Financial_Instrument__c(
                Id = episode.Financial_Instrument__c,
                Calc_Mode__c = episode.Mode_To__c,
                Calc_Mode_Since__c = Datetime.now(),
                Active_Mode_Change__c = episodeId
            );
        }
    }

    public static void returnToEngineMode(Id episodeId, String returnMode, String endReason) {
        Calc_Mode_Change__c episode = [
            SELECT Id, Debt_Position__c, Financial_Instrument__c
            FROM Calc_Mode_Change__c WHERE Id = :episodeId
        ];
        episode.Status__c = 'Closed';
        episode.Return_Mode__c = returnMode;
        episode.End_Date__c = Datetime.now();
        episode.End_Reason__c = endReason;
        update episode;

        if (episode.Debt_Position__c != null) {
            update new Debt_Position__c(
                Id = episode.Debt_Position__c,
                Calc_Mode__c = 'Engine',
                Calc_Mode_Since__c = Datetime.now(),
                Active_Mode_Change__c = null
            );
        } else if (episode.Financial_Instrument__c != null) {
            update new Financial_Instrument__c(
                Id = episode.Financial_Instrument__c,
                Calc_Mode__c = 'Engine',
                Calc_Mode_Since__c = Datetime.now(),
                Active_Mode_Change__c = null
            );
        }
    }
}