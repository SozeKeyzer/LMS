/**
 * GenericDayCountCalculator — implements IDayCountCalculator
 * Reads DayCount_Convention__mdt by Convention_Code to determine numerator/denominator rules.
 * Supports: ACT_365, ACT_360, THIRTY_360_US, THIRTY_360_EU, ACT_ACT_ISDA.
 */
public class GenericDayCountCalculator implements IDayCountCalculator {

    private static Map<String,DayCount_Convention__mdt> conventionCache;

    private static Map<String,DayCount_Convention__mdt> getConventions() {
        if (conventionCache == null) {
            conventionCache = new Map<String,DayCount_Convention__mdt>();
            for (DayCount_Convention__mdt c : [
                SELECT Convention_Code__c, Numerator_Basis__c, Denominator__c, Is_Active__c
                FROM DayCount_Convention__mdt WHERE Is_Active__c = true
            ]) {
                conventionCache.put(c.Convention_Code__c, c);
            }
        }
        return conventionCache;
    }

    public Decimal getDayCountFraction(Date startDate, Date endDate, String convention) {
        if (startDate == null || endDate == null || String.isBlank(convention)) {
            throw new DayCountException('getDayCountFraction: startDate, endDate, and convention are required');
        }

        DayCount_Convention__mdt c = getConventions().get(convention);
        if (c == null) {
            throw new DayCountException('Unknown day count convention: ' + convention);
        }

        Integer numerator;
        Decimal denominator;

        if (c.Numerator_Basis__c == 'Actual') {
            numerator = startDate.daysBetween(endDate);
        } else {
            // 30/360 — both US and EU variants
            Integer d1 = startDate.day(), m1 = startDate.month(), y1 = startDate.year();
            Integer d2 = endDate.day(),   m2 = endDate.month(),   y2 = endDate.year();
            if (convention == 'THIRTY_360_US') {
                if (d1 == 31) d1 = 30;
                if (d2 == 31 && d1 >= 30) d2 = 30;
            } else { // THIRTY_360_EU
                if (d1 == 31) d1 = 30;
                if (d2 == 31) d2 = 30;
            }
            numerator = 360*(y2-y1) + 30*(m2-m1) + (d2-d1);
        }

        if (c.Denominator__c == 0) {
            // ACT/ACT ISDA — split across year-end boundaries per spec Part 3.2.5.
            // Each sub-period uses the actual days in its own calendar year as the denominator.
            if (startDate.year() == endDate.year()) {
                return (Decimal) numerator / (isLeapYear(startDate.year()) ? 366 : 365);
            }
            Decimal fraction = 0;
            Date cursor = startDate;
            while (cursor < endDate) {
                Date nextYearStart = Date.newInstance(cursor.year() + 1, 1, 1);
                Date segmentEnd    = endDate < nextYearStart ? endDate : nextYearStart;
                Integer segDays    = cursor.daysBetween(segmentEnd);
                fraction += (Decimal) segDays / (isLeapYear(cursor.year()) ? 366 : 365);
                cursor = segmentEnd;
            }
            return fraction;
        } else {
            denominator = c.Denominator__c;
        }

        return (Decimal) numerator / denominator;
    }

    private static Boolean isLeapYear(Integer y) {
        return (Math.mod(y, 4) == 0 && Math.mod(y, 100) != 0) || Math.mod(y, 400) == 0;
    }

    @TestVisible
    public static void clearCache() { conventionCache = null; }

    public class DayCountException extends Exception {}
}