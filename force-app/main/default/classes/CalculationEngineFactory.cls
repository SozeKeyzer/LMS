/**
 * CalculationEngineFactory
 * Reads Calc_Strategy__mdt to resolve strategy class names at runtime.
 * No hardcoded class names — add a strategy by adding one MDT record.
 */
public class CalculationEngineFactory {

    private static Map<String,List<Calc_Strategy__mdt>> strategyCache;

    private static Map<String,List<Calc_Strategy__mdt>> getStrategies() {
        if (strategyCache == null) {
            strategyCache = new Map<String,List<Calc_Strategy__mdt>>();
            for (Calc_Strategy__mdt s : [
                SELECT Apex_Class_Name__c, Strategy_Type__c, Is_Active__c
                FROM Calc_Strategy__mdt WHERE Is_Active__c = true
            ]) {
                String key = s.Strategy_Type__c;
                if (!strategyCache.containsKey(key)) {
                    strategyCache.put(key, new List<Calc_Strategy__mdt>());
                }
                strategyCache.get(key).add(s);
            }
        }
        return strategyCache;
    }

    public static IInterestCalculator getInterestCalculator(String rateType) {
        return (IInterestCalculator) Type.forName(resolveClassName('IInterestCalculator', rateType)).newInstance();
    }

    public static IDayCountCalculator getDayCountCalculator() {
        return (IDayCountCalculator) Type.forName(resolveClassName('IDayCountCalculator', null)).newInstance();
    }

    public static IAmortisationCalculator getAmortisationCalculator(String method) {
        return (IAmortisationCalculator) Type.forName(resolveClassName('IAmortisationCalculator', method)).newInstance();
    }

    public static IWaterfallAllocator getWaterfallAllocator(String ruleCode) {
        return (IWaterfallAllocator) Type.forName(resolveClassName('IWaterfallAllocator', ruleCode)).newInstance();
    }

    public static IAccrualPoster getAccrualPoster() {
        return (IAccrualPoster) Type.forName(resolveClassName('IAccrualPoster', null)).newInstance();
    }

    private static String resolveClassName(String strategyType, String strategyHint) {
        List<Calc_Strategy__mdt> candidates = getStrategies().get(strategyType);
        if (candidates == null || candidates.isEmpty()) {
            throw new CalculationEngineException('No active strategy found for type: ' + strategyType);
        }
        if (String.isNotBlank(strategyHint)) {
            String h = strategyHint.toLowerCase().replace('_', '');
            for (Calc_Strategy__mdt s : candidates) {
                if (s.Apex_Class_Name__c.toLowerCase().contains(h)) return s.Apex_Class_Name__c;
            }
            throw new CalculationEngineException('No strategy found for type: ' + strategyType + ', hint: ' + strategyHint);
        }
        return candidates[0].Apex_Class_Name__c;
    }

    public class CalculationEngineException extends Exception {}

    @TestVisible
    public static void clearCache() { strategyCache = null; }
}