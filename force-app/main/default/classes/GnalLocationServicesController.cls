public with sharing class GnalLocationServicesController {

    // Code->label maps for where address fields store only codes (e.g., "VA", "US").
    private static final Map<String, String> STATE_CODE_TO_LABEL = initCodeToLabel(Account.BillingStateCode.getDescribe());
    private static final Map<String, String> COUNTRY_CODE_TO_LABEL = initCodeToLabel(Account.BillingCountryCode.getDescribe());
    private static final Map<String, String> STATE_LABEL_TO_CODE = invertMapCaseInsensitive(STATE_CODE_TO_LABEL);
    private static final Map<String, String> COUNTRY_LABEL_TO_CODE = invertMapCaseInsensitive(COUNTRY_CODE_TO_LABEL);
    private static final String ZIP5_REGEX = '^[0-9]{5}$';

    private static final Integer PARSED_ADDRESS_CACHE_LIMIT = 500;
    private static final Integer MAX_ADDRESS_PARSE_LENGTH = 300;
    private static final Integer LOCATION_SERVICE_CASE_CACHE_LIMIT = 200;
    private static final Integer LOCATION_SERVICE_KEY_CACHE_LIMIT = 500;

    private static final Map<String, Schema.SObjectField> LOCATION_SERVICE_FIELD_MAP =
        Schema.SObjectType.GNAL_Location_Service__c.fields.getMap();
    private static final Map<String, Schema.SObjectField> ACCOUNT_FIELD_MAP =
        Schema.SObjectType.Account.fields.getMap();
    private static final List<String> HOME_ADDRESS_SELECT_FIELDS = initHomeAddressSelectFields();

    private static Map<String, ParsedAddress> PARSED_ADDRESS_CACHE = new Map<String, ParsedAddress>();
    private static Map<Id, String> CASE_DEFAULT_LOCATION_CACHE = new Map<Id, String>();
    private static Map<Id, Id> CASE_TO_ACCOUNT_CACHE = new Map<Id, Id>();
    private static Map<Id, String> ACCOUNT_HOME_LOCATION_CACHE = new Map<Id, String>();
    private static Map<Id, List<GNAL_Location_Service__c>> LOCATION_SERVICES_BY_CASE_CACHE =
        new Map<Id, List<GNAL_Location_Service__c>>();
    private static Map<String, Id> LOCATION_SERVICE_ID_CACHE = new Map<String, Id>();

    public class LocationServiceUpsertResult {
        @AuraEnabled public Id locationServiceId;
        @AuraEnabled public Integer searchCount;
        @AuraEnabled public String currentLocation;
    }

    @AuraEnabled(cacheable=true)
    public static String getDefaultCurrentLocationForCase(Id caseId) {
        if (caseId == null) return null;
        if (!CASE_DEFAULT_LOCATION_CACHE.containsKey(caseId)) {
            loadDefaultLocationsForCases(new Set<Id>{ caseId });
        }
        return CASE_DEFAULT_LOCATION_CACHE.get(caseId);
    }

    private static void loadDefaultLocationsForCases(Set<Id> caseIds) {
        if (caseIds == null || caseIds.isEmpty()) return;

        Set<Id> toLoad = new Set<Id>();
        for (Id caseId : caseIds) {
            if (!CASE_DEFAULT_LOCATION_CACHE.containsKey(caseId)) {
                toLoad.add(caseId);
            }
        }
        if (toLoad.isEmpty()) return;

        Map<Id, Case> casesById = new Map<Id, Case>(
            [SELECT Id, AccountId FROM Case WHERE Id IN :toLoad]
        );
        for (Id caseId : toLoad) {
            Case c = casesById.get(caseId);
            CASE_TO_ACCOUNT_CACHE.put(caseId, c != null ? c.AccountId : null);
        }

        Set<Id> accountIdsToLoad = new Set<Id>();
        for (Id caseId : toLoad) {
            Id accountId = CASE_TO_ACCOUNT_CACHE.get(caseId);
            if (accountId != null && !ACCOUNT_HOME_LOCATION_CACHE.containsKey(accountId)) {
                accountIdsToLoad.add(accountId);
            }
        }

        if (!accountIdsToLoad.isEmpty()) {
            String soql = 'SELECT ' + String.join(HOME_ADDRESS_SELECT_FIELDS, ',') +
                ' FROM Account WHERE Id IN :accountIdsToLoad';
            List<Account> accounts = (List<Account>) Database.query(soql);

            Set<Id> seenAccountIds = new Set<Id>();
            for (Account a : accounts) {
                seenAccountIds.add(a.Id);
                ACCOUNT_HOME_LOCATION_CACHE.put(a.Id, buildHomeAddressFromAccount(a));
            }
            for (Id accountId : accountIdsToLoad) {
                if (!seenAccountIds.contains(accountId)) {
                    ACCOUNT_HOME_LOCATION_CACHE.put(accountId, null);
                }
            }
        }

        for (Id caseId : toLoad) {
            Id accountId = CASE_TO_ACCOUNT_CACHE.get(caseId);
            String addr = accountId != null ? ACCOUNT_HOME_LOCATION_CACHE.get(accountId) : null;
            CASE_DEFAULT_LOCATION_CACHE.put(caseId, addr);
        }
    }

    private static String buildHomeAddressFromAccount(Account a) {
        if (a == null) return null;

        String homeText = getAccountStringIfSelected(a, ACCOUNT_FIELD_MAP, 'GNAL_Home_Address__c');
        if (!String.isBlank(homeText)) return homeText;

        String street = getAccountStringIfSelected(a, ACCOUNT_FIELD_MAP, 'GNAL_Home_Address__Street__s');
        String city = getAccountStringIfSelected(a, ACCOUNT_FIELD_MAP, 'GNAL_Home_Address__City__s');

        String state = getAccountStringIfSelected(a, ACCOUNT_FIELD_MAP, 'GNAL_Home_Address__State__s');
        String stateCode = getAccountStringIfSelected(a, ACCOUNT_FIELD_MAP, 'GNAL_Home_Address__StateCode__s');
        if (String.isBlank(state) && !String.isBlank(stateCode)) {
            state = stateLabelFromCode(stateCode);
        } else if (String.isBlank(state)) {
            state = stateCode;
        }

        String postal = getAccountStringIfSelected(a, ACCOUNT_FIELD_MAP, 'GNAL_Home_Address__PostalCode__s');

        String country = getAccountStringIfSelected(a, ACCOUNT_FIELD_MAP, 'GNAL_Home_Address__Country__s');
        String countryCode = getAccountStringIfSelected(a, ACCOUNT_FIELD_MAP, 'GNAL_Home_Address__CountryCode__s');
        if (String.isBlank(country) && !String.isBlank(countryCode)) {
            country = countryLabelFromCode(countryCode);
        } else if (String.isBlank(country)) {
            country = countryCode;
        }

        List<String> parts = new List<String>();
        if (!String.isBlank(street)) parts.add(street);
        if (!String.isBlank(city)) parts.add(city);
        if (!String.isBlank(state)) parts.add(state);
        if (!String.isBlank(postal)) parts.add(postal);
        if (!String.isBlank(country)) parts.add(country);
        return parts.isEmpty() ? null : String.join(parts, ', ');
    }

    private static List<String> initHomeAddressSelectFields() {
        List<String> selectFields = new List<String>{ 'Id' };
        if (ACCOUNT_FIELD_MAP != null && ACCOUNT_FIELD_MAP.containsKey('GNAL_Home_Address__c')) {
            Schema.DescribeFieldResult d = ACCOUNT_FIELD_MAP.get('GNAL_Home_Address__c').getDescribe();
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
                    if (ACCOUNT_FIELD_MAP.containsKey(f)) selectFields.add(f);
                }
            } else {
                selectFields.add('GNAL_Home_Address__c');
            }
        }
        return selectFields;
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

        try {
            return createOrIncrementLocationServiceInternal(caseId, normalized);
        } catch (System.ListException ex) {
            logException('Location Service list error', ex);
            return createOrIncrementLocationServiceFallback(caseId, normalized);
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            logException('Location Service upsert failed', ex);
            throw new AuraHandledException('Unable to create Location Service. Please try again.');
        }
    }

    private static LocationServiceUpsertResult createOrIncrementLocationServiceInternal(Id caseId, String normalized) {
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

        cacheLocationServiceId(buildLocationServiceKey(caseId, normalized), ls.Id);
        touchLocationServiceCaseCache(caseId, ls);

        return buildLocationServiceResult(ls, normalized);
    }

    private static LocationServiceUpsertResult createOrIncrementLocationServiceFallback(Id caseId, String normalized) {
        Id matchId = queryLatestLocationServiceId(
            'WHERE GNAL_Case__c = \'' + String.escapeSingleQuotes(String.valueOf(caseId)) + '\''
        );

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
            writeCurrentLocationMinimal(ls, normalized);
            update ls;
        } else {
            ls = new GNAL_Location_Service__c();
            ls.GNAL_Case__c = caseId;
            ls.GNAL_Search_Count__c = 1;
            writeCurrentLocationMinimal(ls, normalized);
            insert ls;
        }

        cacheLocationServiceId(buildLocationServiceKey(caseId, normalized), ls.Id);
        touchLocationServiceCaseCache(caseId, ls);

        return buildLocationServiceResult(ls, normalized);
    }

    private static LocationServiceUpsertResult buildLocationServiceResult(
        GNAL_Location_Service__c ls,
        String normalized
    ) {
        LocationServiceUpsertResult out = new LocationServiceUpsertResult();
        out.locationServiceId = ls != null ? ls.Id : null;
        out.currentLocation = normalized;
        out.searchCount = (ls != null && ls.GNAL_Search_Count__c != null)
            ? Integer.valueOf(ls.GNAL_Search_Count__c)
            : null;
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

        String cacheKey = buildLocationServiceKey(caseId, normalized);
        if (LOCATION_SERVICE_ID_CACHE.containsKey(cacheKey)) {
            return LOCATION_SERVICE_ID_CACHE.get(cacheKey);
        }

        Map<String, Schema.SObjectField> fields = LOCATION_SERVICE_FIELD_MAP;
        Boolean hasStreet = fields != null && fields.containsKey('GNAL_Current_Location__Street__s');

        List<GNAL_Location_Service__c> rows = getLocationServicesForCase(caseId);
        Id matchId;

        if (hasStreet) {
            ParsedAddress parsed = parseNormalizedAddress(normalized);
            String streetVal = (parsed != null && !String.isBlank(parsed.street)) ? parsed.street : normalized;

            for (GNAL_Location_Service__c row : rows) {
                String rowStreet = getStringField(row, 'GNAL_Current_Location__Street__s');
                if (!stringEquals(rowStreet, streetVal)) {
                    continue;
                }
                if (!matchesParsedAddress(row, parsed, fields)) {
                    continue;
                }
                matchId = row.Id;
                break;
            }
        } else {
            matchId = rows.isEmpty() ? null : rows[0].Id;
        }

        cacheLocationServiceId(cacheKey, matchId);
        return matchId;
    }

    private static List<GNAL_Location_Service__c> getLocationServicesForCase(Id caseId) {
        if (caseId == null) return new List<GNAL_Location_Service__c>();
        if (!LOCATION_SERVICES_BY_CASE_CACHE.containsKey(caseId)) {
            loadLocationServicesForCases(new Set<Id>{ caseId });
        }
        List<GNAL_Location_Service__c> rows = LOCATION_SERVICES_BY_CASE_CACHE.get(caseId);
        return rows == null ? new List<GNAL_Location_Service__c>() : rows;
    }

    private static void loadLocationServicesForCases(Set<Id> caseIds) {
        if (caseIds == null || caseIds.isEmpty()) return;

        Set<Id> toLoad = new Set<Id>();
        for (Id caseId : caseIds) {
            if (!LOCATION_SERVICES_BY_CASE_CACHE.containsKey(caseId)) {
                toLoad.add(caseId);
            }
        }
        if (toLoad.isEmpty()) return;

        if (LOCATION_SERVICES_BY_CASE_CACHE.size() >= LOCATION_SERVICE_CASE_CACHE_LIMIT) {
            LOCATION_SERVICES_BY_CASE_CACHE.clear();
        }

        List<String> selectFields = new List<String>{ 'Id', 'GNAL_Case__c', 'CreatedDate' };
        if (LOCATION_SERVICE_FIELD_MAP != null) {
            List<String> candidates = new List<String>{
                'GNAL_Current_Location__Street__s',
                'GNAL_Current_Location__City__s',
                'GNAL_Current_Location__State__s',
                'GNAL_Current_Location__StateCode__s',
                'GNAL_Current_Location__PostalCode__s',
                'GNAL_Current_Location__Country__s',
                'GNAL_Current_Location__CountryCode__s'
            };
            for (String f : candidates) {
                if (LOCATION_SERVICE_FIELD_MAP.containsKey(f)) {
                    selectFields.add(f);
                }
            }
        }

        List<GNAL_Location_Service__c> rows = new List<GNAL_Location_Service__c>();
        try {
            String soql =
                'SELECT ' + String.join(selectFields, ',') +
                ' FROM GNAL_Location_Service__c' +
                ' WHERE GNAL_Case__c IN :toLoad' +
                ' ORDER BY CreatedDate DESC';
            rows = (List<GNAL_Location_Service__c>) Database.query(soql);
        } catch (Exception ex) {
            logException('Location Service query failed', ex);
        }

        Map<Id, List<GNAL_Location_Service__c>> grouped = new Map<Id, List<GNAL_Location_Service__c>>();
        for (GNAL_Location_Service__c row : rows) {
            if (row == null || row.GNAL_Case__c == null) continue;
            if (!grouped.containsKey(row.GNAL_Case__c)) {
                grouped.put(row.GNAL_Case__c, new List<GNAL_Location_Service__c>());
            }
            grouped.get(row.GNAL_Case__c).add(row);
        }

        for (Id caseId : toLoad) {
            List<GNAL_Location_Service__c> listForCase = grouped.containsKey(caseId)
                ? grouped.get(caseId)
                : new List<GNAL_Location_Service__c>();
            LOCATION_SERVICES_BY_CASE_CACHE.put(caseId, listForCase);
        }
    }

    private static Boolean matchesParsedAddress(
        GNAL_Location_Service__c row,
        ParsedAddress parsed,
        Map<String, Schema.SObjectField> fields
    ) {
        if (row == null || parsed == null || fields == null) return true;

        if (fields.containsKey('GNAL_Current_Location__City__s') && !String.isBlank(parsed.city)) {
            if (!stringEqualsIgnoreCase(getStringField(row, 'GNAL_Current_Location__City__s'), parsed.city)) {
                return false;
            }
        }

        if (!String.isBlank(parsed.state)) {
            if (fields.containsKey('GNAL_Current_Location__State__s')) {
                String expected = stateLabelFromCode(parsed.state);
                if (!stringEqualsIgnoreCase(getStringField(row, 'GNAL_Current_Location__State__s'), expected)) {
                    return false;
                }
            } else if (fields.containsKey('GNAL_Current_Location__StateCode__s')) {
                String expectedCode = stateCodeFromInput(parsed.state);
                if (!stringEqualsIgnoreCase(getStringField(row, 'GNAL_Current_Location__StateCode__s'), expectedCode)) {
                    return false;
                }
            }
        }

        if (fields.containsKey('GNAL_Current_Location__PostalCode__s') && !String.isBlank(parsed.postal)) {
            if (!stringEqualsIgnoreCase(getStringField(row, 'GNAL_Current_Location__PostalCode__s'), parsed.postal)) {
                return false;
            }
        }

        if (!String.isBlank(parsed.country)) {
            if (fields.containsKey('GNAL_Current_Location__Country__s')) {
                String expectedCountry = countryLabelFromCode(parsed.country);
                if (!stringEqualsIgnoreCase(getStringField(row, 'GNAL_Current_Location__Country__s'), expectedCountry)) {
                    return false;
                }
            } else if (fields.containsKey('GNAL_Current_Location__CountryCode__s')) {
                String expectedCode = countryCodeFromInput(parsed.country);
                if (!stringEqualsIgnoreCase(getStringField(row, 'GNAL_Current_Location__CountryCode__s'), expectedCode)) {
                    return false;
                }
            }
        }

        return true;
    }

    private static void cacheLocationServiceId(String cacheKey, Id locationServiceId) {
        if (String.isBlank(cacheKey)) return;
        if (LOCATION_SERVICE_ID_CACHE.size() >= LOCATION_SERVICE_KEY_CACHE_LIMIT) {
            LOCATION_SERVICE_ID_CACHE.clear();
        }
        LOCATION_SERVICE_ID_CACHE.put(cacheKey, locationServiceId);
    }

    private static void touchLocationServiceCaseCache(Id caseId, GNAL_Location_Service__c record) {
        if (caseId == null || record == null) return;
        if (!LOCATION_SERVICES_BY_CASE_CACHE.containsKey(caseId)) return;

        List<GNAL_Location_Service__c> rows = LOCATION_SERVICES_BY_CASE_CACHE.get(caseId);
        if (rows == null) rows = new List<GNAL_Location_Service__c>();

        for (Integer i = rows.size() - 1; i >= 0; i--) {
            if (rows[i] != null && rows[i].Id == record.Id) {
                rows.remove(i);
            }
        }
        rows.add(0, record);
        LOCATION_SERVICES_BY_CASE_CACHE.put(caseId, rows);
    }

    private static String buildLocationServiceKey(Id caseId, String normalized) {
        return String.valueOf(caseId) + '|' + String.valueOf(normalized);
    }

    private static Id queryLatestLocationServiceId(String whereClause) {
        String w = String.isBlank(whereClause) ? '' : (' ' + whereClause.trim());
        try {
            List<GNAL_Location_Service__c> rows = (List<GNAL_Location_Service__c>) Database.query(
                'SELECT Id' +
                ' FROM GNAL_Location_Service__c' +
                w +
                ' ORDER BY CreatedDate DESC' +
                ' LIMIT 1'
            );
            return rows.isEmpty() ? null : rows[0].Id;
        } catch (Exception ex) {
            logException('Location Service lookup failed', ex);
            return null;
        }
    }

    /**
     * GNAL_Current_Location__c is an Address field in the org.
     * We write subfields. Store the full normalized address in Street; best-effort parse the rest.
     */
    private static void writeCurrentLocation(GNAL_Location_Service__c ls, String normalized) {
        if (ls == null || String.isBlank(normalized)) return;

        Map<String, Schema.SObjectField> fields = Schema.SObjectType.GNAL_Location_Service__c.fields.getMap();
        if (fields == null) return;

        ParsedAddress parsed = parseNormalizedAddress(normalized);

        // Prefer writing to the compound subfields for clean display:
        // Street
        // City, State Postal
        // Country
        String streetVal = (parsed != null && !String.isBlank(parsed.street)) ? parsed.street : normalized;
        putIfWriteable(ls, fields, 'GNAL_Current_Location__Street__s', streetVal);

        if (parsed != null) {
            if (!String.isBlank(parsed.city)) {
                putIfWriteable(ls, fields, 'GNAL_Current_Location__City__s', parsed.city);
            }
            if (!String.isBlank(parsed.state)) {
                // Some orgs expose State__s, some StateCode__s, some both. Write whatever exists.
                putIfWriteable(ls, fields, 'GNAL_Current_Location__State__s', stateLabelFromCode(parsed.state));
                putIfWriteable(ls, fields, 'GNAL_Current_Location__StateCode__s', stateCodeFromInput(parsed.state));
            }
            if (!String.isBlank(parsed.postal)) {
                putIfWriteable(ls, fields, 'GNAL_Current_Location__PostalCode__s', parsed.postal);
            }
            if (!String.isBlank(parsed.country)) {
                putIfWriteable(ls, fields, 'GNAL_Current_Location__Country__s', countryLabelFromCode(parsed.country));
                putIfWriteable(ls, fields, 'GNAL_Current_Location__CountryCode__s', countryCodeFromInput(parsed.country));
            }
        }
    }

    private static void writeCurrentLocationMinimal(GNAL_Location_Service__c ls, String normalized) {
        if (ls == null || String.isBlank(normalized)) return;
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.GNAL_Location_Service__c.fields.getMap();
        if (fields == null) return;

        if (fields.containsKey('GNAL_Current_Location__Street__s')) {
            putIfWriteable(ls, fields, 'GNAL_Current_Location__Street__s', normalized);
            return;
        }

        if (fields.containsKey('GNAL_Current_Location__c')) {
            Schema.DescribeFieldResult d = fields.get('GNAL_Current_Location__c').getDescribe();
            if (d != null && d.getType() != Schema.DisplayType.Address) {
                putIfWriteable(ls, fields, 'GNAL_Current_Location__c', normalized);
            }
        }
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

    private static String getStringField(SObject row, String api) {
        if (row == null || String.isBlank(api)) return null;
        Object v = row.get(api);
        return (v instanceof String) ? (String) v : null;
    }

    private static Boolean stringEquals(String a, String b) {
        if (a == null && b == null) return true;
        if (a == null || b == null) return false;
        return a == b;
    }

    private static Boolean stringEqualsIgnoreCase(String a, String b) {
        if (a == null && b == null) return true;
        if (a == null || b == null) return false;
        return a.toLowerCase() == b.toLowerCase();
    }

    private static String normalizeAddress(String address) {
        if (address == null) return null;
        // Collapse any repeated whitespace to a single space.
        return address.trim().replaceAll('\\s+', ' ');
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

    private static Map<String, String> initCodeToLabel(Schema.DescribeFieldResult describe) {
        Map<String, String> out = new Map<String, String>();
        try {
            if (describe == null) return out;
            for (Schema.PicklistEntry e : describe.getPicklistValues()) {
                if (e == null) continue;
                String code = e.getValue();
                String label = e.getLabel();
                if (!String.isBlank(code) && !String.isBlank(label)) out.put(code, label);
            }
        } catch (Exception ex) {
            // ignore; fall back to raw codes
        }
        return out;
    }

    private static String stateLabelFromCode(String code) {
        if (String.isBlank(code)) return null;
        String trimmed = code.trim();
        if (STATE_CODE_TO_LABEL != null && STATE_CODE_TO_LABEL.containsKey(trimmed)) {
            return STATE_CODE_TO_LABEL.get(trimmed);
        }
        return trimmed;
    }

    private static String stateCodeFromInput(String stateOrCode) {
        if (String.isBlank(stateOrCode)) return null;
        String trimmed = stateOrCode.trim();
        // Already a code?
        if (STATE_CODE_TO_LABEL != null && STATE_CODE_TO_LABEL.containsKey(trimmed)) return trimmed;
        // Try label->code map (case-insensitive)
        String key = trimmed.toLowerCase();
        if (STATE_LABEL_TO_CODE != null && STATE_LABEL_TO_CODE.containsKey(key)) {
            return STATE_LABEL_TO_CODE.get(key);
        }
        return trimmed;
    }

    private static String countryLabelFromCode(String code) {
        if (String.isBlank(code)) return null;
        String trimmed = code.trim();
        if (COUNTRY_CODE_TO_LABEL != null && COUNTRY_CODE_TO_LABEL.containsKey(trimmed)) {
            return COUNTRY_CODE_TO_LABEL.get(trimmed);
        }
        // Common best-effort default if picklists aren't enabled/configured.
        if (trimmed == 'US') return 'United States';
        return trimmed;
    }

    private static String countryCodeFromInput(String countryOrCode) {
        if (String.isBlank(countryOrCode)) return null;
        String trimmed = countryOrCode.trim();
        if (COUNTRY_CODE_TO_LABEL != null && COUNTRY_CODE_TO_LABEL.containsKey(trimmed)) return trimmed;
        String key = trimmed.toLowerCase();
        if (COUNTRY_LABEL_TO_CODE != null && COUNTRY_LABEL_TO_CODE.containsKey(key)) {
            return COUNTRY_LABEL_TO_CODE.get(key);
        }
        // Common best-effort default if picklists aren't enabled/configured.
        if (trimmed == 'United States') return 'US';
        return trimmed;
    }

    private static Map<String, String> invertMapCaseInsensitive(Map<String, String> input) {
        Map<String, String> out = new Map<String, String>();
        if (input == null) return out;
        for (String code : input.keySet()) {
            String label = input.get(code);
            if (String.isBlank(code) || String.isBlank(label)) continue;
            out.put(label.toLowerCase(), code);
        }
        return out;
    }

    private class ParsedAddress {
        String street;
        String city;
        String state;
        String postal;
        String country;
    }

    /**
     * Best-effort parse of a single-line address string into parts that map to Salesforce Address subfields.
     *
     * Supports common shapes:
     * - "street, city, state, postal, country"
     * - "street, city, state postal, country"
     * - "street, city state postal, country"
     *
     * If parsing is uncertain, we at least return Street=original string so data isn't lost.
     */
    private static ParsedAddress parseNormalizedAddress(String normalized) {
        if (String.isBlank(normalized)) return null;

        String cacheKey = normalized.trim();
        if (PARSED_ADDRESS_CACHE.containsKey(cacheKey)) {
            return PARSED_ADDRESS_CACHE.get(cacheKey);
        }

        if (cacheKey.length() > MAX_ADDRESS_PARSE_LENGTH) {
            ParsedAddress out = new ParsedAddress();
            out.street = cacheKey;
            cacheParsedAddress(cacheKey, out);
            return out;
        }

        // Normalize whitespace and strip newlines for parsing.
        String s = cacheKey.replaceAll('[\\r\\n]+', ' ').trim().replaceAll('\\s+', ' ');
        List<String> tokens = splitTrim(s, ',');

        ParsedAddress out = new ParsedAddress();
        if (tokens.isEmpty()) {
            out.street = s;
            cacheParsedAddress(cacheKey, out);
            return out;
        }

        // Most common: street, city, state, postal, country (5 tokens)
        if (tokens.size() >= 5) {
            Integer n = tokens.size();
            out.country = tokens[n - 1];
            out.postal = tokens[n - 2];
            out.state = tokens[n - 3];
            out.city = tokens[n - 4];
            // Street may itself contain commas (suite/building). Join the remaining prefix.
            List<String> streetParts = new List<String>();
            for (Integer i = 0; i <= n - 5; i++) streetParts.add(tokens[i]);
            out.street = String.join(streetParts, ', ');
            cacheParsedAddress(cacheKey, out);
            return out;
        }

        // Common: street, city, "state postal", country (4 tokens)
        if (tokens.size() == 4) {
            out.street = tokens[0];
            out.city = tokens[1];
            out.country = tokens[3];
            String statePostal = tokens[2];
            ParsedAddress sp = parseStatePostal(statePostal);
            out.state = sp != null ? sp.state : null;
            out.postal = sp != null ? sp.postal : null;
            if (String.isBlank(out.state)) out.state = statePostal;
            cacheParsedAddress(cacheKey, out);
            return out;
        }

        // Less common: street, "city state postal", country (3 tokens)
        if (tokens.size() == 3) {
            out.street = tokens[0];
            out.country = tokens[2];
            ParsedAddress csp = parseCityStatePostal(tokens[1]);
            if (csp != null) {
                out.city = csp.city;
                out.state = csp.state;
                out.postal = csp.postal;
            } else {
                out.city = tokens[1];
            }
            cacheParsedAddress(cacheKey, out);
            return out;
        }

        // Minimal: treat as Street-only.
        out.street = s;
        cacheParsedAddress(cacheKey, out);
        return out;
    }

    private static void cacheParsedAddress(String cacheKey, ParsedAddress parsed) {
        if (String.isBlank(cacheKey)) return;
        if (PARSED_ADDRESS_CACHE.size() >= PARSED_ADDRESS_CACHE_LIMIT) {
            PARSED_ADDRESS_CACHE.clear();
        }
        PARSED_ADDRESS_CACHE.put(cacheKey, parsed);
    }

    private static ParsedAddress parseStatePostal(String value) {
        if (String.isBlank(value)) return null;
        List<String> parts = splitTrim(value, ' ');
        if (parts.size() < 2) return null;
        String last = parts[parts.size() - 1];
        // Simple US ZIP check (5 digits)
        if (!Pattern.matches(ZIP5_REGEX, last)) return null;

        ParsedAddress out = new ParsedAddress();
        out.postal = last;
        List<String> stateParts = new List<String>();
        for (Integer i = 0; i < parts.size() - 1; i++) stateParts.add(parts[i]);
        out.state = String.join(stateParts, ' ');
        return out;
    }

    private static ParsedAddress parseCityStatePostal(String value) {
        if (String.isBlank(value)) return null;
        // Try "City State Postal" where postal is 5 digits.
        List<String> parts = splitTrim(value, ' ');
        if (parts.size() < 3) return null;

        String postal = parts[parts.size() - 1];
        if (!Pattern.matches(ZIP5_REGEX, postal)) return null;

        String state = parts[parts.size() - 2];
        List<String> cityParts = new List<String>();
        for (Integer i = 0; i < parts.size() - 2; i++) cityParts.add(parts[i]);
        String city = String.join(cityParts, ' ');

        ParsedAddress out = new ParsedAddress();
        out.city = city;
        out.state = state;
        out.postal = postal;
        return out;
    }

    private static List<String> splitTrim(String raw, String delimiter) {
        List<String> out = new List<String>();
        if (String.isBlank(raw) || String.isBlank(delimiter)) return out;
        for (String p : raw.split(delimiter)) {
            String t = p == null ? null : p.trim();
            if (!String.isBlank(t)) out.add(t);
        }
        return out;
    }

    private static void logException(String prefix, Exception ex) {
        if (ex == null) {
            System.debug(LoggingLevel.ERROR, prefix + ': Unknown exception (null)');
            return;
        }
        System.debug(
            LoggingLevel.ERROR,
            prefix + ': ' + ex.getTypeName() +
            ' (line ' + String.valueOf(ex.getLineNumber()) + ') ' +
            ex.getMessage() + '\n' +
            ex.getStackTraceString()
        );
    }
}
