/**
 * CorrelationIdGenerator
 * Generates a UUID v4 compatible string using Salesforce Crypto API.
 * Format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
 */
public class CorrelationIdGenerator {
    public static String generate() {
        Blob b = Crypto.generateAesKey(128);
        String h = EncodingUtil.convertToHex(b);
        return h.substring(0,8)  + '-' +
               h.substring(8,12) + '-' +
               '4' + h.substring(13,16) + '-' +
               '8' + h.substring(17,20) + '-' +
               h.substring(20,32);
    }
}
