public with sharing class GnalLocationServicesController {

    // Code->label maps for orgs where address fields store only codes (e.g., "VA", "US").
    private static final Map<String, String> STATE_CODE_TO_LABEL =
        buildCodeLabelMap(safeDescribe('Account', 'BillingStateCode'));
    private static final Map<String, String> COUNTRY_CODE_TO_LABEL =
        buildCodeLabelMap(safeDescribe('Account', 'BillingCountryCode'));
    private static final Map<String, String> STATE_LABEL_TO_CODE = buildLabelCodeMap(STATE_CODE_TO_LABEL);
    private static final Map<String, String> COUNTRY_LABEL_TO_CODE = buildLabelCodeMap(COUNTRY_CODE_TO_LABEL);

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

        String state = getAccountStringIfSelected(a, accFields, 'GNAL_Home_Address__State__s');
        String stateCode = getAccountStringIfSelected(a, accFields, 'GNAL_Home_Address__StateCode__s');
        if (String.isBlank(state) && !String.isBlank(stateCode)) {
            state = stateLabelFromCode(stateCode);
        } else if (String.isBlank(state)) {
            state = stateCode;
        }

        String postal = getAccountStringIfSelected(a, accFields, 'GNAL_Home_Address__PostalCode__s');

        String country = getAccountStringIfSelected(a, accFields, 'GNAL_Home_Address__Country__s');
        String countryCode = getAccountStringIfSelected(a, accFields, 'GNAL_Home_Address__CountryCode__s');
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
            ParsedAddress parsed = parseNormalizedAddress(normalized);
            // If parsing fails, fall back to matching on Street only.
            String streetVal = (parsed != null && !String.isBlank(parsed.street)) ? parsed.street : normalized;

            // Build a schema-aware query that matches on subfields when available.
            List<String> whereClauses = new List<String>();
            whereClauses.add('GNAL_Case__c = \'' + String.escapeSingleQuotes(String.valueOf(caseId)) + '\'');
            whereClauses.add('GNAL_Current_Location__Street__s = \'' + String.escapeSingleQuotes(streetVal) + '\'');

            if (parsed != null) {
                if (fields.containsKey('GNAL_Current_Location__City__s') && !String.isBlank(parsed.city)) {
                    whereClauses.add('GNAL_Current_Location__City__s = \'' + String.escapeSingleQuotes(parsed.city) + '\'');
                }
                if (fields.containsKey('GNAL_Current_Location__State__s') && !String.isBlank(parsed.state)) {
                    whereClauses.add('GNAL_Current_Location__State__s = \'' + String.escapeSingleQuotes(stateLabelFromCode(parsed.state)) + '\'');
                } else if (fields.containsKey('GNAL_Current_Location__StateCode__s') && !String.isBlank(parsed.state)) {
                    whereClauses.add('GNAL_Current_Location__StateCode__s = \'' + String.escapeSingleQuotes(stateCodeFromInput(parsed.state)) + '\'');
                }
                if (fields.containsKey('GNAL_Current_Location__PostalCode__s') && !String.isBlank(parsed.postal)) {
                    whereClauses.add('GNAL_Current_Location__PostalCode__s = \'' + String.escapeSingleQuotes(parsed.postal) + '\'');
                }
                if (fields.containsKey('GNAL_Current_Location__Country__s') && !String.isBlank(parsed.country)) {
                    whereClauses.add('GNAL_Current_Location__Country__s = \'' + String.escapeSingleQuotes(countryLabelFromCode(parsed.country)) + '\'');
                } else if (fields.containsKey('GNAL_Current_Location__CountryCode__s') && !String.isBlank(parsed.country)) {
                    whereClauses.add('GNAL_Current_Location__CountryCode__s = \'' + String.escapeSingleQuotes(countryCodeFromInput(parsed.country)) + '\'');
                }
            }

            List<GNAL_Location_Service__c> rows = (List<GNAL_Location_Service__c>) Database.query(
                'SELECT Id' +
                ' FROM GNAL_Location_Service__c' +
                ' WHERE ' + String.join(whereClauses, ' AND ') +
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

    private static Schema.DescribeFieldResult safeDescribe(String sobjectApiName, String fieldApiName) {
        try {
            Schema.SObjectType t = Schema.getGlobalDescribe().get(sobjectApiName);
            if (t == null) return null;
            Map<String, Schema.SObjectField> m = t.getDescribe().fields.getMap();
            if (m == null || !m.containsKey(fieldApiName)) return null;
            return m.get(fieldApiName).getDescribe();
        } catch (Exception ex) {
            return null;
        }
    }

    private static Map<String, String> buildCodeLabelMap(Schema.DescribeFieldResult d) {
        Map<String, String> out = new Map<String, String>();
        try {
            if (d == null) return out;
            for (Schema.PicklistEntry e : d.getPicklistValues()) {
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

    private static Map<String, String> buildLabelCodeMap(Map<String, String> codeLabel) {
        Map<String, String> out = new Map<String, String>();
        if (codeLabel == null) return out;
        for (String code : codeLabel.keySet()) {
            String label = codeLabel.get(code);
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

        // Normalize whitespace and strip newlines for parsing.
        String s = normalized.replace('\n', ' ').replace('\r', ' ');
        while (s.contains('  ')) s = s.replace('  ', ' ');
        s = s.trim();

        ParsedAddress out = new ParsedAddress();
        List<String> tokens = splitTrim(s, ',');
        if (tokens.isEmpty()) return withStreet(out, s);

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
            return out;
        }

        // Common: street, city, "state postal", country (4 tokens)
        if (tokens.size() == 4) {
            out.street = tokens[0];
            out.city = tokens[1];
            out.country = tokens[3];
            ParsedAddress sp = parseStatePostalTokens(splitTrim(tokens[2], ' '));
            if (sp != null) {
                out.state = sp.state;
                out.postal = sp.postal;
            } else {
                out.state = tokens[2];
            }
            return out;
        }

        // Less common: street, "city state postal", country (3 tokens)
        if (tokens.size() == 3) {
            out.street = tokens[0];
            out.country = tokens[2];
            ParsedAddress csp = parseCityStatePostalTokens(splitTrim(tokens[1], ' '));
            if (csp == null) return withCity(out, tokens[1]);
            out.city = csp.city;
            out.state = csp.state;
            out.postal = csp.postal;
            return out;
        }

        // Minimal: treat as Street-only.
        return withStreet(out, s);
    }

    private static ParsedAddress parseStatePostalTokens(List<String> parts) {
        if (parts == null || parts.size() < 2) return null;
        String postal = parts[parts.size() - 1];
        if (!isZip5(postal)) return null;
        ParsedAddress out = new ParsedAddress();
        out.postal = postal;
        out.state = String.join(parts.subList(0, parts.size() - 1), ' ');
        return out;
    }

    private static ParsedAddress parseCityStatePostalTokens(List<String> parts) {
        if (parts == null || parts.size() < 3) return null;
        String postal = parts[parts.size() - 1];
        if (!isZip5(postal)) return null;
        ParsedAddress out = new ParsedAddress();
        out.postal = postal;
        out.state = parts[parts.size() - 2];
        out.city = String.join(parts.subList(0, parts.size() - 2), ' ');
        return out;
    }

    private static Boolean isZip5(String value) {
        if (String.isBlank(value)) return false;
        String v = value.trim();
        if (v.length() != 5) return false;
        for (Integer i = 0; i < 5; i++) {
            String ch = v.substring(i, i + 1);
            if (ch < '0' || ch > '9') return false;
        }
        return true;
    }

    private static List<String> splitTrim(String s, String delimiterChar) {
        List<String> out = new List<String>();
        if (String.isBlank(s) || String.isBlank(delimiterChar)) return out;
        for (String raw : s.split(delimiterChar)) {
            String t = raw == null ? null : raw.trim();
            if (!String.isBlank(t)) out.add(t);
        }
        return out;
    }

    private static ParsedAddress withStreet(ParsedAddress a, String street) {
        a.street = street;
        return a;
    }

    private static ParsedAddress withCity(ParsedAddress a, String city) {
        a.city = city;
        return a;
    }
}

