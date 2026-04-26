/**
 * CalcContext
 * Immutable DTO carrying everything a strategy needs to run.
 * All SOQL happens BEFORE context is built. Strategies are SOQL-free.
 * Uses the Builder pattern so optional fields default to null cleanly.
 */
public class CalcContext {
    public final Id     debtPositionId;
    public final Decimal principal;
    public final Decimal interestRate;
    public final String  dayCountConvention;
    public final String  amortisationMethod;
    public final String  interestTreatment;
    public final String  waterfallRule;
    public final Date    periodStartDate;
    public final Date    periodEndDate;
    public final Date    calculationDate;
    public final String  engineMode;
    public final String  correlationId;
    public final Map<String,Object> extras;

    private CalcContext(Builder b) {
        this.debtPositionId    = b.debtPositionId;
        this.principal         = b.principal;
        this.interestRate      = b.interestRate;
        this.dayCountConvention= b.dayCountConvention;
        this.amortisationMethod= b.amortisationMethod;
        this.interestTreatment = b.interestTreatment;
        this.waterfallRule     = b.waterfallRule;
        this.periodStartDate   = b.periodStartDate;
        this.periodEndDate     = b.periodEndDate;
        this.calculationDate   = b.calculationDate;
        this.engineMode        = b.engineMode;
        this.correlationId     = b.correlationId;
        this.extras            = b.extras != null ? b.extras.clone() : new Map<String,Object>();
    }

    public class Builder {
        private Id     debtPositionId;
        private Decimal principal;
        private Decimal interestRate;
        private String  dayCountConvention;
        private String  amortisationMethod;
        private String  interestTreatment;
        private String  waterfallRule;
        private Date    periodStartDate;
        private Date    periodEndDate;
        private Date    calculationDate;
        private String  engineMode;
        private String  correlationId;
        private Map<String,Object> extras;

        public Builder setDebtPositionId(Id v)     { debtPositionId=v;     return this; }
        public Builder setPrincipal(Decimal v)      { principal=v;          return this; }
        public Builder setInterestRate(Decimal v)   { interestRate=v;       return this; }
        public Builder setDayCountConvention(String v){ dayCountConvention=v; return this; }
        public Builder setAmortisationMethod(String v){ amortisationMethod=v; return this; }
        public Builder setInterestTreatment(String v){ interestTreatment=v; return this; }
        public Builder setWaterfallRule(String v)   { waterfallRule=v;      return this; }
        public Builder setPeriodStartDate(Date v)   { periodStartDate=v;    return this; }
        public Builder setPeriodEndDate(Date v)     { periodEndDate=v;      return this; }
        public Builder setCalculationDate(Date v)   { calculationDate=v;    return this; }
        public Builder setEngineMode(String v)      { engineMode=v;         return this; }
        public Builder setCorrelationId(String v)   { correlationId=v;      return this; }
        public Builder setExtras(Map<String,Object> v){ extras=v;           return this; }

        public CalcContext build() { return new CalcContext(this); }
    }
}
