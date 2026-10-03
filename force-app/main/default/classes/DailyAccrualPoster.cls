/**
 * DailyAccrualPoster — implements IAccrualPoster
 * Creates one Accrual_Daily__c record per Debt_Position per day.
 * Idempotent via External_Id (DPId-AccrualDate). Enforces Rule R10.
 * In Preview mode: returns record in EngineResult without inserting.
 * In Apply mode: upsert by External_Id.
 */
public class DailyAccrualPoster extends CalculationEngineBase implements IAccrualPoster {

    public DailyAccrualPoster() { super(Mode.APPLY); }

    public EngineResult postDailyAccrual(Date accrualDate, CalcContext ctx) {
        EngineResult result = new EngineResult();

        Boolean isPIK        = (Boolean)(ctx.extras.get('isPIK') ?? false);
        String  ipId         = (String)  ctx.extras.get('interestPeriodId');
        Decimal dayCountFrac = (Decimal)(ctx.extras.get('dayCountFraction') ?? 0);
        String  electionType = (String)  ctx.extras.get('electionType');

        Decimal principal    = ctx.principal    != null ? ctx.principal    : 0;
        Decimal rate         = ctx.interestRate != null ? ctx.interestRate : 0;
        Decimal totalAccrued = principal * (rate / 100) * dayCountFrac;

        String baseId = String.valueOf(ctx.debtPositionId) + '-' + accrualDate.format();

        // Split election: borrow-side elected a partial PIK / partial cash split.
        // Create two rows so each can age independently and roll up correctly.
        if (electionType == 'Split') {
            return buildSplitRows(ctx, accrualDate, ipId, dayCountFrac, principal, rate, totalAccrued, baseId);
        }

        // Full PIK or full cash — single row
        Accrual_Daily__c accrual = buildRow(
            ctx.debtPositionId, ipId, accrualDate, principal, rate, dayCountFrac,
            totalAccrued, isPIK, ctx.correlationId, baseId
        );
        result.addInsert(accrual);
        result.setAmount(totalAccrued);
        result.setResultType('Daily_Accrual');
        return result;
    }

    // Two rows for Split elections: cash portion + PIK portion
    // The election's Cash_Amount__c / PIK_Amount__c are period totals; we prorate to a single day.
    private EngineResult buildSplitRows(
        CalcContext ctx, Date accrualDate, String ipId, Decimal dcf,
        Decimal principal, Decimal rate, Decimal totalAccrued, String baseId
    ) {
        EngineResult result = new EngineResult();

        // Elected amounts are period-level totals; split them proportionally to the daily total
        Decimal elCash = ctx.extras.get('electionCashAmt') != null
                            ? (Decimal) ctx.extras.get('electionCashAmt') : 0;
        Decimal elPIK  = ctx.extras.get('electionPIKAmt')  != null
                            ? (Decimal) ctx.extras.get('electionPIKAmt')  : 0;
        Decimal elTotal = elCash + elPIK;

        Decimal cashPct = (elTotal > 0) ? (elCash / elTotal) : 1.0;
        Decimal pikPct  = 1.0 - cashPct;

        Decimal cashAmount = (totalAccrued * cashPct).setScale(2, RoundingMode.HALF_EVEN);
        Decimal pikAmount  = (totalAccrued - cashAmount).setScale(2, RoundingMode.HALF_EVEN);

        if (cashAmount > 0) {
            result.addInsert(buildRow(ctx.debtPositionId, ipId, accrualDate, principal, rate, dcf,
                cashAmount, false, ctx.correlationId, baseId + '-CASH'));
        }
        if (pikAmount > 0) {
            result.addInsert(buildRow(ctx.debtPositionId, ipId, accrualDate, principal, rate, dcf,
                pikAmount, true, ctx.correlationId, baseId + '-PIK'));
        }

        result.setAmount(totalAccrued);
        result.setResultType('Daily_Accrual_Split');
        return result;
    }

    private static Accrual_Daily__c buildRow(
        Id dpId, String ipId, Date accrualDate, Decimal principal, Decimal rate,
        Decimal dcf, Decimal amount, Boolean isPIK, String corrId, String externalId
    ) {
        return new Accrual_Daily__c(
            Debt_Position__c       = dpId,
            Interest_Period__c     = ipId,
            Accrual_Date__c        = accrualDate,
            Principal_Basis__c     = principal,
            Rate__c                = rate,
            Day_Count_Fraction__c  = dcf,
            Accrued_Amount__c      = amount,
            Calculated_Value__c    = amount,
            Is_PIK__c              = isPIK,
            Status__c              = 'Accrued',
            Is_Immutable__c        = false,
            Correlation_Id__c      = corrId,
            Source__c              = 'System_Calculated',
            Engine_Version__c      = CalculationEngineBase.ENGINE_VERSION,
            External_Id__c         = externalId
        );
    }

    public override EngineResult execute(CalcContext ctx) {
        Date d = ctx.calculationDate != null ? ctx.calculationDate : Date.today();
        return postDailyAccrual(d, ctx);
    }
}