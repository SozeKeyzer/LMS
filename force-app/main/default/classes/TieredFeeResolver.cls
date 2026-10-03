/**
 * TieredFeeResolver
 * Selects the applicable Fee_Tier__c band for a Fee_Structures record at a point in time.
 * Same band-resolution pattern as MarginRatchetEvaluator.BandResolver.
 * Returns null when the Fee_Structure has no Fee_Tier children (flat fee structure — caller
 * reads Fee_Structures.Applicable_Rate directly).
 * Spec v3 Part 6.10, v7 Part 5.2.9.
 */
public class TieredFeeResolver {

    /**
     * Resolve the applicable tier for a Fee_Structures record at a given date.
     *
     * @param fs        Fee_Structures__c record (must have Debt_Position__c populated)
     * @param asOfDate  The date to evaluate utilisation (typically fee period close date)
     * @return Applicable Fee_Tier__c record, or null if no tiers defined (flat fee)
     */
    public static Fee_Tier__c resolveTier(Fee_Structures__c fs, Date asOfDate) {
        List<Fee_Tier__c> tiers = [
            SELECT Id, Tier_Order__c, Threshold_Lower__c, Threshold_Upper__c,
                   Threshold_Basis__c, Applicable_Rate__c
            FROM Fee_Tier__c
            WHERE Fee_Structure__c = :fs.Id
            ORDER BY Tier_Order__c ASC
        ];
        if (tiers.isEmpty()) return null; // flat fee — caller reads fs.Applicable_Rate__c directly

        // All tiers in a Fee_Structure share the same basis by convention
        String basis = tiers[0].Threshold_Basis__c != null ? tiers[0].Threshold_Basis__c : 'Utilisation_Percent';
        Decimal value = computeBasisValue(fs.Debt_Position__c, basis, asOfDate);

        for (Fee_Tier__c tier : tiers) {
            Boolean withinLower = (tier.Threshold_Lower__c == null || value >= tier.Threshold_Lower__c);
            Boolean withinUpper = (tier.Threshold_Upper__c == null || value <= tier.Threshold_Upper__c);
            if (withinLower && withinUpper) return tier;
        }
        throw new TieredFeeException('No tier found for basis value ' + value
            + ' on Fee_Structures ' + fs.Id + '. Check tier coverage is exhaustive.');
    }

    /**
     * Compute the basis value (utilisation %, drawn $, or undrawn $) for a DP as of a date.
     */
    public static Decimal computeBasisValue(Id dpId, String basis, Date asOfDate) {
        if (basis == 'Utilisation_Percent') {
            Debt_Position__c dp = [
                SELECT Outstanding_Balance__c, Position_Notional__c
                FROM Debt_Position__c
                WHERE Id = :dpId
            ];
            Decimal notional = dp.Position_Notional__c != null && dp.Position_Notional__c > 0
                ? dp.Position_Notional__c : 1;
            return (dp.Outstanding_Balance__c != null ? dp.Outstanding_Balance__c : 0) / notional;
        }

        if (basis == 'Drawn_Amount') {
            AggregateResult[] agg = [
                SELECT SUM(Amount__c) total
                FROM Disbursement_Event__c
                WHERE Debt_Position__c = :dpId
                  AND Value_Date__c <= :asOfDate
            ];
            return (agg != null && !agg.isEmpty() && agg[0].get('total') != null)
                ? (Decimal) agg[0].get('total') : 0;
        }

        if (basis == 'Undrawn_Amount') {
            Debt_Position__c dp = [SELECT Position_Notional__c FROM Debt_Position__c WHERE Id = :dpId];
            AggregateResult[] agg = [
                SELECT SUM(Amount__c) total
                FROM Disbursement_Event__c
                WHERE Debt_Position__c = :dpId
                  AND Value_Date__c <= :asOfDate
            ];
            Decimal drawn = (agg != null && !agg.isEmpty() && agg[0].get('total') != null)
                ? (Decimal) agg[0].get('total') : 0;
            Decimal notional = dp.Position_Notional__c != null ? dp.Position_Notional__c : 0;
            return Math.max(0, notional - drawn);
        }

        throw new TieredFeeException('Unknown Threshold_Basis: ' + basis);
    }

    public class TieredFeeException extends Exception {}
}