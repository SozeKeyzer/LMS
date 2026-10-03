/**
 * RateFixingIngestionService
 * Spec v5 Part 2.8.3: on fixing ingestion, triggers rate finalisation workflow.
 * Idempotent via External_Id on Rate_Index_Fixing.
 * After upsert: calls PaymentScheduleRateFinaliser to transition Projected_Rate → Rate_Finalised
 * on Payment_Schedule rows whose period rate set date has now been published.
 */
public class RateFixingIngestionService {

    public static void ingest(List<Rate_Index_Fixing__c> fixings) {

        // Split: records queried from DB already have an Id — update them directly.
        // New records (no Id) go through upsert by External_Id to enforce idempotency.
        List<Rate_Index_Fixing__c> toUpdate = new List<Rate_Index_Fixing__c>();
        List<Rate_Index_Fixing__c> toUpsert = new List<Rate_Index_Fixing__c>();

        for (Rate_Index_Fixing__c f : fixings) {
            if (String.isBlank(f.External_Id__c)) {
                f.External_Id__c = String.valueOf(f.Rate_Index__c) + '-' + f.Fixing_Date__c.format();
            }
            f.Ingestion_Timestamp__c = DateTime.now();
            f.Source__c = 'External_Integration';
            if (f.Id != null) {
                toUpdate.add(f);
            } else {
                toUpsert.add(f);
            }
        }

        List<Rate_Index_Fixing__c> successfulFixings = new List<Rate_Index_Fixing__c>();

        if (!toUpdate.isEmpty()) {
            List<Database.SaveResult> updateResults = Database.update(toUpdate, false);
            System.debug('Update results: ' + updateResults);
            for (Integer i = 0; i < updateResults.size(); i++) {
                if (updateResults[i].isSuccess()) successfulFixings.add(toUpdate[i]);
            }
        }

        if (!toUpsert.isEmpty()) {
            Schema.SObjectField extIdField = Rate_Index_Fixing__c.Fields.External_Id__c;
            List<Database.UpsertResult> upsertResults = Database.upsert(toUpsert, extIdField, false);
            System.debug('Upsert results: ' + upsertResults);
            for (Integer i = 0; i < upsertResults.size(); i++) {
                if (upsertResults[i].isSuccess()) successfulFixings.add(toUpsert[i]);
            }
        }

        if (!successfulFixings.isEmpty()) {
            PaymentScheduleRateFinaliser.finaliseForFixings(successfulFixings);
        }

        AuditEventLogger.logEngine('RATE_FIXING_INGESTED','Rate_Index_Fixing__c',null,
            'Ingested ' + toUpsert.size() + ' rate fixings. Finalisation triggered for '
            + successfulFixings.size() + ' new fixings.');
        AuditEventLogger.flush();
    }
}