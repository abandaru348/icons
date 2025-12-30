public with sharing class GnalLocationServicesController {

    public class LocationServiceUpsertResult {
        @AuraEnabled public Id locationServiceId;
        @AuraEnabled public Integer searchCount;
        @AuraEnabled public String currentLocation;
    }

    @AuraEnabled(cacheable=true)
    public static String getDefaultCurrentLocationForCase(Id caseId) {
        if (caseId == null) return null;

        Case c = [SELECT Id, AccountId FROM Case WHERE Id = :caseId LIMIT 1];
        if (c.AccountId == null) return null;

        // Person Account home address fields exist only when Person Accounts are enabled.
        Map<String, Schema.SObjectField> accFields = Schema.SObjectType.Account.fields.getMap();
        List<String> selectFields = new List<String>{ 'Id' };

        // Prefer Person Home address fields when available.
        List<String> homeFields = new List<String>{
            'PersonHomeStreet',
            'PersonHomeCity',
            'PersonHomeState',
            'PersonHomeStateCode',
            'PersonHomePostalCode',
            'PersonHomeCountry',
            'PersonHomeCountryCode'
        };
        for (String f : homeFields) {
            if (accFields != null && accFields.containsKey(f)) selectFields.add(f);
        }

        // As a fallback, pull billing address if home address fields are not present.
        if (selectFields.size() == 1) {
            selectFields.addAll(new List<String>{
                'BillingStreet','BillingCity','BillingState','BillingStateCode','BillingPostalCode','BillingCountry','BillingCountryCode'
            });
        }

        String soql =
            'SELECT ' + String.join(selectFields, ',') +
            ' FROM Account WHERE Id = \'' + String.escapeSingleQuotes(String.valueOf(c.AccountId)) + '\'' +
            ' LIMIT 1';
        Account a = (Account) Database.query(soql);

        // Build address from home if present, else billing.
        String street = coalesceStr(a.get('PersonHomeStreet'), a.get('BillingStreet'));
        String city = coalesceStr(a.get('PersonHomeCity'), a.get('BillingCity'));
        // Prefer *Code fields when present (State/Country picklists)
        String state = coalesceStr(a.get('PersonHomeStateCode'), a.get('PersonHomeState'), a.get('BillingStateCode'), a.get('BillingState'));
        String postal = coalesceStr(a.get('PersonHomePostalCode'), a.get('BillingPostalCode'));
        String country = coalesceStr(a.get('PersonHomeCountryCode'), a.get('PersonHomeCountry'), a.get('BillingCountryCode'), a.get('BillingCountry'));

        List<String> parts = new List<String>();
        if (!String.isBlank(street)) parts.add(street);
        if (!String.isBlank(city)) parts.add(city);
        if (!String.isBlank(state)) parts.add(state);
        if (!String.isBlank(postal)) parts.add(postal);
        if (!String.isBlank(country)) parts.add(country);
        return parts.isEmpty() ? null : String.join(parts, ', ');
    }

    @AuraEnabled(cacheable=false)
    public static LocationServiceUpsertResult createOrIncrementLocationService(Id caseId, String currentLocation) {
        if (caseId == null) {
            throw new AuraHandledException('Case Id is required.');
        }
        String normalized = normalizeAddress(currentLocation);
        if (String.isBlank(normalized)) {
            throw new AuraHandledException('Current Location is required.');
        }

        String key = buildCaseLocationKey(caseId, normalized);

        // Lock the row if it exists to avoid double-increment on concurrent clicks.
        List<Location_Services__c> existing = [
            SELECT Id, Search_Count__c, Current_Location__c
            FROM Location_Services__c
            WHERE Case_Location_Key__c = :key
            LIMIT 1
            FOR UPDATE
        ];

        Location_Services__c ls;
        if (!existing.isEmpty()) {
            ls = existing[0];
            Integer nextCount = (ls.Search_Count__c == null) ? 1 : Integer.valueOf(ls.Search_Count__c) + 1;
            ls.Search_Count__c = nextCount;
            // Keep the latest normalized value.
            ls.Current_Location__c = normalized;
            update ls;
        } else {
            ls = new Location_Services__c();
            ls.Case__c = caseId;
            ls.Current_Location__c = normalized;
            ls.Case_Location_Key__c = key;
            ls.Search_Count__c = 1;
            insert ls;
        }

        LocationServiceUpsertResult out = new LocationServiceUpsertResult();
        out.locationServiceId = ls.Id;
        out.currentLocation = normalized;
        out.searchCount = (ls.Search_Count__c == null) ? null : Integer.valueOf(ls.Search_Count__c);
        return out;
    }

    private static String buildCaseLocationKey(Id caseId, String normalizedLocation) {
        // Keep it deterministic and <= 255.
        String raw = String.valueOf(caseId) + '|' + normalizedLocation;
        if (raw.length() <= 255) return raw;
        // Fall back to a hash when very long.
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(raw))).left(255);
    }

    private static String normalizeAddress(String address) {
        if (address == null) return null;
        String s = address.trim();
        // Collapse repeated whitespace
        while (s.contains('  ')) s = s.replace('  ', ' ');
        return s;
    }

    private static String coalesceStr(Object a, Object b) {
        return coalesceStr(new List<Object>{ a, b });
    }
    private static String coalesceStr(Object a, Object b, Object c, Object d) {
        return coalesceStr(new List<Object>{ a, b, c, d });
    }
    private static String coalesceStr(List<Object> vals) {
        for (Object v : vals) {
            if (v instanceof String && !String.isBlank((String) v)) return (String) v;
        }
        return null;
    }
}

