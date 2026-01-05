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

        Map<String, Schema.SObjectField> accFields = Schema.SObjectType.Account.fields.getMap();
        List<String> selectFields = new List<String>{ 'Id' };

        // GNAL Home Address (could be Text or Address). If Address, select only subfields that exist.
        if (accFields != null && accFields.containsKey('GNAL_Home_Address__c')) {
            Schema.DescribeFieldResult d = accFields.get('GNAL_Home_Address__c').getDescribe();
            if (d != null && d.getType() == Schema.DisplayType.Address) {
                List<String> homeCandidates = new List<String>{
                    'GNAL_Home_Address__Street__s',
                    'GNAL_Home_Address__City__s',
                    'GNAL_Home_Address__StateCode__s',
                    'GNAL_Home_Address__State__s',
                    'GNAL_Home_Address__PostalCode__s',
                    'GNAL_Home_Address__CountryCode__s',
                    'GNAL_Home_Address__Country__s'
                };
                for (String f : homeCandidates) {
                    if (accFields.containsKey(f)) selectFields.add(f);
                }
            } else {
                // Text/other: query directly
                selectFields.add('GNAL_Home_Address__c');
            }
        }

        Account a = (Account) Database.query(
            'SELECT ' + String.join(selectFields, ',') +
            ' FROM Account WHERE Id = \'' + String.escapeSingleQuotes(String.valueOf(c.AccountId)) + '\'' +
            ' LIMIT 1'
        );

        // If GNAL_Home_Address__c is Text and populated, prefer it.
        String homeText = getAccountStringIfSelected(a, accFields, 'GNAL_Home_Address__c');
        if (!String.isBlank(homeText)) return homeText;

        // Otherwise build from available home subfields only (no Billing fallback).
        String street = getAccountStringIfSelected(a, accFields, 'GNAL_Home_Address__Street__s');
        String city = getAccountStringIfSelected(a, accFields, 'GNAL_Home_Address__City__s');

        String state = coalesceStr(
            getAccountStringIfSelected(a, accFields, 'GNAL_Home_Address__StateCode__s'),
            getAccountStringIfSelected(a, accFields, 'GNAL_Home_Address__State__s')
        );

        String postal = getAccountStringIfSelected(a, accFields, 'GNAL_Home_Address__PostalCode__s');

        String country = coalesceStr(
            getAccountStringIfSelected(a, accFields, 'GNAL_Home_Address__CountryCode__s'),
            getAccountStringIfSelected(a, accFields, 'GNAL_Home_Address__Country__s')
        );

        List<String> parts = new List<String>();
        if (!String.isBlank(street)) parts.add(street);
        if (!String.isBlank(city)) parts.add(city);
        if (!String.isBlank(state)) parts.add(state);
        if (!String.isBlank(postal)) parts.add(postal);
        if (!String.isBlank(country)) parts.add(country);
        return parts.isEmpty() ? null : String.join(parts, ', ');
    }

    /**
     * Behavior:
     * - If the same Case searches the same normalized address multiple times, increment the same record.
     * - If the address changes (Account updated or user manually entered a different address), create a new record.
     */
    @AuraEnabled(cacheable=false)
    public static LocationServiceUpsertResult createOrIncrementLocationService(Id caseId, String currentLocation) {
        if (caseId == null) throw new AuraHandledException('Case Id is required.');
        String normalized = normalizeAddress(currentLocation);
        if (String.isBlank(normalized)) throw new AuraHandledException('Current Location is required.');

        Id matchId = findLatestLocationServiceIdByCaseAndNormalizedAddress(caseId, normalized);

        GNAL_Location_Service__c ls;
        if (matchId != null) {
            ls = [
                SELECT Id, GNAL_Search_Count__c
                FROM GNAL_Location_Service__c
                WHERE Id = :matchId
                LIMIT 1
                FOR UPDATE
            ];

            Integer nextCount = (ls.GNAL_Search_Count__c == null)
                ? 1
                : Integer.valueOf(ls.GNAL_Search_Count__c) + 1;

            ls.GNAL_Search_Count__c = nextCount;
            writeCurrentLocation(ls, normalized);
            update ls;
        } else {
            ls = new GNAL_Location_Service__c();
            ls.GNAL_Case__c = caseId;
            ls.GNAL_Search_Count__c = 1;
            writeCurrentLocation(ls, normalized);
            insert ls;
        }

        LocationServiceUpsertResult out = new LocationServiceUpsertResult();
        out.locationServiceId = ls.Id;
        out.currentLocation = normalized;
        out.searchCount = (ls.GNAL_Search_Count__c == null) ? null : Integer.valueOf(ls.GNAL_Search_Count__c);
        return out;
    }

    /**
     * Finds the most recent Location Service record for the Case whose stored normalized
     * address matches the incoming normalized value.
     *
     * We store the full normalized address in the Address Street subfield, so we match on
     * GNAL_Current_Location__Street__s when that field exists.
     *
     * If the org doesn't have that field for any reason, fall back to "latest record" behavior.
     */
    private static Id findLatestLocationServiceIdByCaseAndNormalizedAddress(Id caseId, String normalized) {
        if (caseId == null || String.isBlank(normalized)) return null;

        Map<String, Schema.SObjectField> fields = Schema.SObjectType.GNAL_Location_Service__c.fields.getMap();
        Boolean hasStreet = fields != null && fields.containsKey('GNAL_Current_Location__Street__s');

        if (hasStreet) {
            List<GNAL_Location_Service__c> rows = (List<GNAL_Location_Service__c>) Database.query(
                'SELECT Id' +
                ' FROM GNAL_Location_Service__c' +
                ' WHERE GNAL_Case__c = \'' + String.escapeSingleQuotes(String.valueOf(caseId)) + '\'' +
                ' AND GNAL_Current_Location__Street__s = \'' + String.escapeSingleQuotes(normalized) + '\'' +
                ' ORDER BY CreatedDate DESC' +
                ' LIMIT 1'
            );
            return rows.isEmpty() ? null : rows[0].Id;
        }

        // Fallback: preserve prior behavior (latest for Case), but this cannot satisfy address-based grouping.
        List<GNAL_Location_Service__c> latest = (List<GNAL_Location_Service__c>) Database.query(
            'SELECT Id' +
            ' FROM GNAL_Location_Service__c' +
            ' WHERE GNAL_Case__c = \'' + String.escapeSingleQuotes(String.valueOf(caseId)) + '\'' +
            ' ORDER BY CreatedDate DESC' +
            ' LIMIT 1'
        );
        return latest.isEmpty() ? null : latest[0].Id;
    }

    /**
     * GNAL_Current_Location__c is an Address field in your org.
     * We write subfields. Store the full normalized address in Street; best-effort parse the rest.
     */
    private static void writeCurrentLocation(GNAL_Location_Service__c ls, String normalized) {
        if (ls == null || String.isBlank(normalized)) return;

        Map<String, Schema.SObjectField> fields = Schema.SObjectType.GNAL_Location_Service__c.fields.getMap();
        if (fields == null) return;

        putIfWriteable(ls, fields, 'GNAL_Current_Location__Street__s', normalized);

        List<String> parts = new List<String>();
        for (String p : normalized.split(',')) {
            String t = (p == null) ? null : p.trim();
            if (!String.isBlank(t)) parts.add(t);
        }

        if (parts.size() >= 2) putIfWriteable(ls, fields, 'GNAL_Current_Location__City__s', parts[1]);
        if (parts.size() >= 3) putIfWriteable(ls, fields, 'GNAL_Current_Location__State__s', parts[2]);
        if (parts.size() >= 4) putIfWriteable(ls, fields, 'GNAL_Current_Location__PostalCode__s', parts[3]);
        if (parts.size() >= 5) putIfWriteable(ls, fields, 'GNAL_Current_Location__Country__s', parts[4]);
    }

    private static void putIfWriteable(SObject row, Map<String, Schema.SObjectField> fields, String api, Object val) {
        if (row == null || fields == null || String.isBlank(api) || val == null) return;
        if (!fields.containsKey(api)) return;
        Schema.DescribeFieldResult d = fields.get(api).getDescribe();
        if (d != null && (d.isCreateable() || d.isUpdateable())) {
            row.put(api, val);
        }
    }

    private static String getAccountStringIfSelected(SObject row, Map<String, Schema.SObjectField> fields, String api) {
        if (row == null || fields == null || String.isBlank(api)) return null;
        if (!fields.containsKey(api)) return null;

        Map<String, Object> populated = row.getPopulatedFieldsAsMap();
        if (populated == null || !populated.containsKey(api)) return null;

        Object v = populated.get(api);
        return (v instanceof String) ? (String) v : null;
    }

    private static String normalizeAddress(String address) {
        if (address == null) return null;
        String s = address.trim();
        while (s.contains('  ')) s = s.replace('  ', ' ');
        return s;
    }

    private static String coalesceStr(Object a, Object b) {
        return coalesceStrList(new List<Object>{ a, b });
    }
    private static String coalesceStr(Object a, Object b, Object c, Object d) {
        return coalesceStrList(new List<Object>{ a, b, c, d });
    }
    private static String coalesceStrList(List<Object> vals) {
        for (Object v : vals) {
            if (v instanceof String && !String.isBlank((String) v)) return (String) v;
        }
        return null;
    }
}

