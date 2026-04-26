/**
 * IAccrualPoster
 * Implemented by: DailyAccrualPoster (Phase 1)
 * Responsible for building and writing Accrual_Daily__c records.
 */
public interface IAccrualPoster {
    /**
     * Build one Accrual_Daily__c record for the given date and context.
     * In Preview mode: returns the record in EngineResult without inserting.
     * In Commit mode: inserts the record.
     * @return EngineResult with recordsToInsert containing the Accrual_Daily__c
     */
    EngineResult postDailyAccrual(Date accrualDate, CalcContext ctx);
}
