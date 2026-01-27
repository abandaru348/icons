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
    private static final String LOCATION_SERVICES_RECORDTYPE_LABEL = 'Location Services';
    private static Id LOCATION_SERVICES_CASE_RECORDTYPE_ID;

    private static final Map<String, Schema.SObjectField> LOCATION_SERVICE_FIELD_MAP =
        Schema.SObjectType.GNAL_Location_Service__c.fields.getMap();
    private static final Map<String, Schema.SObjectField> ACCOUNT_FIELD_MAP =
        Schema.SObjectType.Account.fields.getMap();
    private static final Map<String, Schema.SObjectField> CONTACT_FIELD_MAP =
        Schema.SObjectType.Contact.fields.getMap();
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

    public class PortalCaseResult {
        @AuraEnabled public Id caseId;
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

    @AuraEnabled(cacheable=true)
    public static String getDefaultCurrentLocationForPortalUser() {
        try {
            String directAddr = loadPortalAddressFromUserRelationship();
            if (!String.isBlank(directAddr)) return directAddr;

            PortalContext context = getPortalContext();
            if (context == null || context.accountId == null) return null;
            if (!ACCOUNT_HOME_LOCATION_CACHE.containsKey(context.accountId)) {
                loadHomeLocationsForAccounts(new Set<Id>{ context.accountId }, true);
            }
            String addr = ACCOUNT_HOME_LOCATION_CACHE.get(context.accountId);
            if (String.isBlank(addr) && context.contactId != null) {
                addr = loadHomeLocationFromContact(context.contactId);
                if (!String.isBlank(addr)) {
                    ACCOUNT_HOME_LOCATION_CACHE.put(context.accountId, addr);
                }
            }
            return addr;
        } catch (Exception ex) {
            logException('Portal default location lookup failed', ex);
            return null;
        }
    }

    @AuraEnabled(cacheable=false)
    public static PortalCaseResult createPortalCaseAndLocationService(String currentLocation, Integer resultCount) {
        if (String.isBlank(currentLocation)) {
            throw new AuraHandledException('Current Location is required.');
        }

        PortalContext context = getPortalContext();
        if (context == null || context.accountId == null) {
            throw new AuraHandledException('Unable to determine the account for the current user.');
        }

        Id recordTypeId = getLocationServicesCaseRecordTypeId();
        if (recordTypeId == null) {
            throw new AuraHandledException('Location Services case record type is not configured.');
        }

        Case c = new Case();
        c.RecordTypeId = recordTypeId;
        c.AccountId = context.accountId;
        if (context.contactId != null) {
            c.ContactId = context.contactId;
        }

        try {
            insert c;
        } catch (DmlException ex) {
            if (isUnableToLockRow(ex)) {
                throw new AuraHandledException('This record is being updated by another user. Please try again.');
            }
            throw ex;
        }

        LocationServiceUpsertResult ls = createOrIncrementLocationServiceIfResults(
            c.Id,
            currentLocation,
            resultCount
        );

        PortalCaseResult out = new PortalCaseResult();
        out.caseId = c.Id;
        if (ls != null) {
            out.locationServiceId = ls.locationServiceId;
            out.searchCount = ls.searchCount;
            out.currentLocation = ls.currentLocation;
        }
        return out;
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

    private class PortalContext {
        Id userId;
        Id contactId;
        Id accountId;
    }

    private static PortalContext getPortalContext() {
        try {
            Map<String, Schema.SObjectField> userFields = Schema.SObjectType.User.fields.getMap();
            String contactField = null;
            String contactRelationship = null;
            String accountField = null;

            if (userFields != null) {
                for (String api : userFields.keySet()) {
                    Schema.SObjectField f = userFields.get(api);
                    Schema.DescribeFieldResult d = f != null ? f.getDescribe() : null;
                    if (d == null || d.getType() != Schema.DisplayType.Reference) {
                        continue;
                    }
                    List<Schema.SObjectType> refs = d.getReferenceTo();
                    if (refs == null) continue;
                    for (Schema.SObjectType refType : refs) {
                        if (refType == Contact.SObjectType && contactField == null) {
                            contactField = api;
                            contactRelationship = d.getRelationshipName();
                        } else if (refType == Account.SObjectType && accountField == null) {
                            accountField = api;
                        }
                    }
                }
            }

            Id userId = UserInfo.getUserId();
            List<String> selectFields = new List<String>{ 'Id' };
            if (!String.isBlank(contactField)) selectFields.add(contactField);
            if (!String.isBlank(accountField) && accountField != contactField) {
                selectFields.add(accountField);
            }
            if (!String.isBlank(contactRelationship)) {
                selectFields.add(contactRelationship + '.AccountId');
            }

            String soql = 'SELECT ' + String.join(selectFields, ',') +
                ' FROM User WHERE Id = :userId' +
                ' LIMIT 1';
            User u = (User) Database.query(soql);
            if (u == null) return null;

            Id contactId = !String.isBlank(contactField) ? (Id) u.get(contactField) : null;
            Id accountId = !String.isBlank(accountField) ? (Id) u.get(accountField) : null;

            if (accountId == null && !String.isBlank(contactRelationship)) {
                SObject contactObj = u.getSObject(contactRelationship);
                if (contactObj != null) {
                    accountId = (Id) contactObj.get('AccountId');
                }
            }

            if (accountId == null && contactId != null) {
                Contact c = [
                    SELECT Id, AccountId
                    FROM Contact
                    WHERE Id = :contactId
                    LIMIT 1
                ];
                accountId = c != null ? c.AccountId : null;
            }

            if (accountId == null) return null;

            PortalContext context = new PortalContext();
            context.userId = u.Id;
            context.contactId = contactId;
            context.accountId = accountId;
            return context;
        } catch (Exception ex) {
            logException('Portal context lookup failed', ex);
            return null;
        }
    }

    private static void loadHomeLocationsForAccounts(Set<Id> accountIds) {
        loadHomeLocationsForAccounts(accountIds, false);
    }

    private static void loadHomeLocationsForAccounts(Set<Id> accountIds, Boolean includeFallback) {
        if (accountIds == null || accountIds.isEmpty()) return;

        Set<Id> toLoad = new Set<Id>();
        for (Id accountId : accountIds) {
            if (!ACCOUNT_HOME_LOCATION_CACHE.containsKey(accountId)) {
                toLoad.add(accountId);
            }
        }
        if (toLoad.isEmpty()) return;

        String soql = 'SELECT ' + String.join(HOME_ADDRESS_SELECT_FIELDS, ',') +
            ' FROM Account WHERE Id IN :toLoad';
        List<Account> accounts = (List<Account>) Database.query(soql);

        Set<Id> seenAccountIds = new Set<Id>();
        for (Account a : accounts) {
            seenAccountIds.add(a.Id);
            String addr = includeFallback ? buildPortalHomeAddressFromAccount(a) : buildHomeAddressFromAccount(a);
            ACCOUNT_HOME_LOCATION_CACHE.put(a.Id, addr);
        }
        for (Id accountId : toLoad) {
            if (!seenAccountIds.contains(accountId)) {
                ACCOUNT_HOME_LOCATION_CACHE.put(accountId, null);
            }
        }
    }

    private static String loadPortalAddressFromUserRelationship() {
        try {
            User u = [
                SELECT Contact.AccountId,
                       Contact.MailingStreet,
                       Contact.MailingCity,
                       Contact.MailingState,
                       Contact.MailingPostalCode,
                       Contact.MailingCountry,
                       Contact.OtherStreet,
                       Contact.OtherCity,
                       Contact.OtherState,
                       Contact.OtherPostalCode,
                       Contact.OtherCountry
                FROM User
                WHERE Id = :UserInfo.getUserId()
                LIMIT 1
            ];
            if (u == null || u.Contact == null) return null;

            Contact c = u.Contact;
            Id accountId = c.AccountId;
            String addr = buildPortalHomeAddressFromContact(c);
            if (String.isBlank(addr)) {
                if (accountId != null) {
                    if (!ACCOUNT_HOME_LOCATION_CACHE.containsKey(accountId)) {
                        loadHomeLocationsForAccounts(new Set<Id>{ accountId }, true);
                    }
                    addr = ACCOUNT_HOME_LOCATION_CACHE.get(accountId);
                }
            }

            if (accountId != null && !String.isBlank(addr)) {
                ACCOUNT_HOME_LOCATION_CACHE.put(accountId, addr);
            }
            return addr;
        } catch (Exception ex) {
            logException('Portal user relationship lookup failed', ex);
            return null;
        }
    }

    private static String loadHomeLocationFromContact(Id contactId) {
        if (contactId == null) return null;
        Contact c = [
            SELECT MailingStreet, MailingCity, MailingState, MailingPostalCode, MailingCountry,
                   OtherStreet, OtherCity, OtherState, OtherPostalCode, OtherCountry
            FROM Contact
            WHERE Id = :contactId
            LIMIT 1
        ];
        return buildPortalHomeAddressFromContact(c);
    }

    private static Id getLocationServicesCaseRecordTypeId() {
        if (LOCATION_SERVICES_CASE_RECORDTYPE_ID != null) {
            return LOCATION_SERVICES_CASE_RECORDTYPE_ID;
        }
        try {
            Map<String, Schema.RecordTypeInfo> byName = Schema.SObjectType.Case.getRecordTypeInfosByName();
            if (byName != null && byName.containsKey(LOCATION_SERVICES_RECORDTYPE_LABEL)) {
                Schema.RecordTypeInfo info = byName.get(LOCATION_SERVICES_RECORDTYPE_LABEL);
                LOCATION_SERVICES_CASE_RECORDTYPE_ID = info != null ? info.getRecordTypeId() : null;
                return LOCATION_SERVICES_CASE_RECORDTYPE_ID;
            }

            RecordType rt = [
                SELECT Id
                FROM RecordType
                WHERE SObjectType = 'Case'
                AND Name = :LOCATION_SERVICES_RECORDTYPE_LABEL
                LIMIT 1
            ];
            LOCATION_SERVICES_CASE_RECORDTYPE_ID = rt != null ? rt.Id : null;
        } catch (Exception ex) {
            logException('Location Services record type lookup failed', ex);
            LOCATION_SERVICES_CASE_RECORDTYPE_ID = null;
        }
        return LOCATION_SERVICES_CASE_RECORDTYPE_ID;
    }

    private static String buildHomeAddressFromAccount(Account a) {
        if (a == null) return null;

        String compoundHome = buildAddressFromCompound(a.get('GNAL_Home_Address__c'));
        if (!String.isBlank(compoundHome)) return compoundHome;

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

    private static String buildPortalHomeAddressFromAccount(Account a) {
        String home = buildHomeAddressFromAccount(a);
        if (!String.isBlank(home)) return home;

        String personMailingCompound = buildAddressFromCompound(a.get('PersonMailingAddress'));
        if (!String.isBlank(personMailingCompound)) return personMailingCompound;

        String personMailing = buildAddressFromStandardFields(
            a,
            'PersonMailingStreet',
            'PersonMailingCity',
            'PersonMailingState',
            'PersonMailingPostalCode',
            'PersonMailingCountry'
        );
        if (!String.isBlank(personMailing)) return personMailing;

        String billing = buildAddressFromCompound(a.get('BillingAddress'));
        if (!String.isBlank(billing)) return billing;

        billing = buildAddressFromStandardFields(
            a,
            'BillingStreet',
            'BillingCity',
            'BillingState',
            'BillingPostalCode',
            'BillingCountry'
        );
        if (!String.isBlank(billing)) return billing;

        String shipping = buildAddressFromCompound(a.get('ShippingAddress'));
        if (!String.isBlank(shipping)) return shipping;

        return buildAddressFromStandardFields(
            a,
            'ShippingStreet',
            'ShippingCity',
            'ShippingState',
            'ShippingPostalCode',
            'ShippingCountry'
        );
    }


    private static String buildPortalHomeAddressFromContact(Contact c) {
        if (c == null) return null;
        String mailingCompound = buildAddressFromCompound(c.get('MailingAddress'));
        if (!String.isBlank(mailingCompound)) return mailingCompound;
        String mailing = buildAddressFromContactFields(
            c,
            'MailingStreet',
            'MailingCity',
            'MailingState',
            'MailingPostalCode',
            'MailingCountry'
        );
        if (!String.isBlank(mailing)) return mailing;

        String otherCompound = buildAddressFromCompound(c.get('OtherAddress'));
        if (!String.isBlank(otherCompound)) return otherCompound;
        return buildAddressFromContactFields(
            c,
            'OtherStreet',
            'OtherCity',
            'OtherState',
            'OtherPostalCode',
            'OtherCountry'
        );
    }

    private static String buildAddressFromContactFields(
        Contact c,
        String streetApi,
        String cityApi,
        String stateApi,
        String postalApi,
        String countryApi
    ) {
        if (c == null) return null;
        String street = getContactStringIfSelected(c, CONTACT_FIELD_MAP, streetApi);
        String city = getContactStringIfSelected(c, CONTACT_FIELD_MAP, cityApi);
        String state = getContactStringIfSelected(c, CONTACT_FIELD_MAP, stateApi);
        String postal = getContactStringIfSelected(c, CONTACT_FIELD_MAP, postalApi);
        String country = getContactStringIfSelected(c, CONTACT_FIELD_MAP, countryApi);

        List<String> parts = new List<String>();
        if (!String.isBlank(street)) parts.add(street);
        if (!String.isBlank(city)) parts.add(city);
        if (!String.isBlank(state)) parts.add(state);
        if (!String.isBlank(postal)) parts.add(postal);
        if (!String.isBlank(country)) parts.add(country);
        return parts.isEmpty() ? null : String.join(parts, ', ');
    }

    private static String buildAddressFromCompound(Object value) {
        if (!(value instanceof Address)) return null;
        Address addr = (Address) value;
        return buildAddressFromParts(addr.street, addr.city, addr.state, addr.postalCode, addr.country);
    }

    private static String buildAddressFromParts(
        String street,
        String city,
        String state,
        String postal,
        String country
    ) {
        List<String> parts = new List<String>();
        if (!String.isBlank(street)) parts.add(street);
        if (!String.isBlank(city)) parts.add(city);
        if (!String.isBlank(state)) parts.add(state);
        if (!String.isBlank(postal)) parts.add(postal);
        if (!String.isBlank(country)) parts.add(country);
        return parts.isEmpty() ? null : String.join(parts, ', ');
    }

    private static String buildAddressFromStandardFields(
        Account a,
        String streetApi,
        String cityApi,
        String stateApi,
        String postalApi,
        String countryApi
    ) {
        if (a == null) return null;
        String street = getAccountStringIfSelected(a, ACCOUNT_FIELD_MAP, streetApi);
        String city = getAccountStringIfSelected(a, ACCOUNT_FIELD_MAP, cityApi);
        String state = getAccountStringIfSelected(a, ACCOUNT_FIELD_MAP, stateApi);
        String postal = getAccountStringIfSelected(a, ACCOUNT_FIELD_MAP, postalApi);
        String country = getAccountStringIfSelected(a, ACCOUNT_FIELD_MAP, countryApi);

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
            if (d != null) {
                // Prefer the compound field itself to avoid missing subfield variants.
                selectFields.add('GNAL_Home_Address__c');
            }
        }

        List<String> portalFallback = new List<String>{
            'PersonMailingAddress',
            'BillingAddress',
            'ShippingAddress'
        };
        for (String f : portalFallback) {
            if (ACCOUNT_FIELD_MAP != null && ACCOUNT_FIELD_MAP.containsKey(f)) {
                selectFields.add(f);
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

    @AuraEnabled(cacheable=false)
    public static List<LocationServiceUpsertResult> createOrIncrementLocationServices(
        List<Id> caseIds,
        List<String> currentLocations
    ) {
        List<LocationServiceUpsertResult> results = new List<LocationServiceUpsertResult>();
        if (caseIds == null || caseIds.isEmpty()) return results;
        if (currentLocations == null || caseIds.size() != currentLocations.size()) {
            throw new AuraHandledException('Case Ids and locations must align.');
        }

        Set<Id> preloadIds = new Set<Id>();
        for (Id caseId : caseIds) {
            if (caseId != null) preloadIds.add(caseId);
        }
        loadLocationServicesForCases(preloadIds);

        for (Integer i = 0; i < caseIds.size(); i++) {
            Id caseId = caseIds[i];
            String location = currentLocations[i];
            if (caseId == null || String.isBlank(location)) {
                results.add(null);
                continue;
            }
            try {
                results.add(createOrIncrementLocationServiceInternal(caseId, normalizeAddress(location)));
            } catch (AuraHandledException ex) {
                // Preserve row-locking and validation messages for callers.
                throw ex;
            } catch (Exception ex) {
                logException('Bulk location service upsert failed', ex);
                results.add(null);
            }
        }
        return results;
    }

    @AuraEnabled(cacheable=false)
    public static LocationServiceUpsertResult createOrIncrementLocationServiceIfResults(
        Id caseId,
        String currentLocation,
        Integer resultCount
    ) {
        if (resultCount == null || resultCount <= 0) {
            return null;
        }
        return createOrIncrementLocationService(caseId, currentLocation);
    }

    private static LocationServiceUpsertResult createOrIncrementLocationServiceInternal(Id caseId, String normalized) {
        GNAL_Location_Service__c matchRow = findLatestLocationServiceByCaseAndNormalizedAddress(caseId, normalized);
        GNAL_Location_Service__c ls;

        if (matchRow != null) {
            ls = matchRow;
            Integer nextCount = (ls.GNAL_Search_Count__c == null)
                ? 1
                : Integer.valueOf(ls.GNAL_Search_Count__c) + 1;
            ls.GNAL_Search_Count__c = nextCount;
            writeCurrentLocation(ls, normalized);
            try {
                update ls;
            } catch (DmlException ex) {
                if (isUnableToLockRow(ex)) {
                    throw new AuraHandledException('This record is being updated by another user. Please try again.');
                }
                throw ex;
            }
        } else {
            ls = new GNAL_Location_Service__c();
            ls.GNAL_Case__c = caseId;
            ls.GNAL_Search_Count__c = 1;
            writeCurrentLocation(ls, normalized);
            try {
                insert ls;
            } catch (DmlException ex) {
                if (isUnableToLockRow(ex)) {
                    throw new AuraHandledException('This record is being updated by another user. Please try again.');
                }
                throw ex;
            }
        }

        cacheLocationServiceId(buildLocationServiceKey(caseId, normalized), ls.Id);
        touchLocationServiceCaseCache(caseId, ls);

        return buildLocationServiceResult(ls, normalized);
    }

    @TestVisible
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
            ];

            Integer nextCount = (ls.GNAL_Search_Count__c == null)
                ? 1
                : Integer.valueOf(ls.GNAL_Search_Count__c) + 1;

            ls.GNAL_Search_Count__c = nextCount;
            writeCurrentLocationMinimal(ls, normalized);
            try {
                update ls;
            } catch (DmlException ex) {
                if (isUnableToLockRow(ex)) {
                    throw new AuraHandledException('This record is being updated by another user. Please try again.');
                }
                throw ex;
            }
        } else {
            ls = new GNAL_Location_Service__c();
            ls.GNAL_Case__c = caseId;
            ls.GNAL_Search_Count__c = 1;
            writeCurrentLocationMinimal(ls, normalized);
            try {
                insert ls;
            } catch (DmlException ex) {
                if (isUnableToLockRow(ex)) {
                    throw new AuraHandledException('This record is being updated by another user. Please try again.');
                }
                throw ex;
            }
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
        GNAL_Location_Service__c row = findLatestLocationServiceByCaseAndNormalizedAddress(caseId, normalized);
        return row == null ? null : row.Id;
    }

    private static GNAL_Location_Service__c findLatestLocationServiceByCaseAndNormalizedAddress(
        Id caseId,
        String normalized
    ) {
        if (caseId == null || String.isBlank(normalized)) return null;

        String cacheKey = buildLocationServiceKey(caseId, normalized);
        List<GNAL_Location_Service__c> rows = getLocationServicesForCase(caseId);
        if (LOCATION_SERVICE_ID_CACHE.containsKey(cacheKey)) {
            Id cachedId = LOCATION_SERVICE_ID_CACHE.get(cacheKey);
            if (cachedId == null) return null;
            for (GNAL_Location_Service__c row : rows) {
                if (row != null && row.Id == cachedId) return row;
            }
        }

        Map<String, Schema.SObjectField> fields = LOCATION_SERVICE_FIELD_MAP;
        Boolean hasStreet = fields != null && fields.containsKey('GNAL_Current_Location__Street__s');
        GNAL_Location_Service__c matchRow;

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
                matchRow = row;
                break;
            }
        } else {
            matchRow = rows.isEmpty() ? null : rows[0];
        }

        cacheLocationServiceId(cacheKey, matchRow != null ? matchRow.Id : null);
        return matchRow;
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

        List<String> selectFields = new List<String>{ 'Id', 'GNAL_Case__c', 'CreatedDate', 'GNAL_Search_Count__c' };
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
            String expectedLabel = normalizeStateLabel(parsed.state);
            if (fields.containsKey('GNAL_Current_Location__State__s') && !String.isBlank(expectedLabel)) {
                if (!stringEqualsIgnoreCase(getStringField(row, 'GNAL_Current_Location__State__s'), expectedLabel)) {
                    return false;
                }
            }
            String expectedCode = normalizeStateCode(parsed.state);
            if (fields.containsKey('GNAL_Current_Location__StateCode__s') && !String.isBlank(expectedCode)) {
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
            String expectedCountry = normalizeCountryLabel(parsed.country);
            if (fields.containsKey('GNAL_Current_Location__Country__s') && !String.isBlank(expectedCountry)) {
                if (!stringEqualsIgnoreCase(getStringField(row, 'GNAL_Current_Location__Country__s'), expectedCountry)) {
                    return false;
                }
            }
            String expectedCode = normalizeCountryCode(parsed.country);
            if (fields.containsKey('GNAL_Current_Location__CountryCode__s') && !String.isBlank(expectedCode)) {
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
        List<GNAL_Location_Service__c> newRows = new List<GNAL_Location_Service__c>();
        newRows.add(record);

        if (rows != null && !rows.isEmpty()) {
            for (GNAL_Location_Service__c row : rows) {
                if (row == null || row.Id == record.Id) {
                    continue;
                }
                newRows.add(row);
            }
        }

        LOCATION_SERVICES_BY_CASE_CACHE.put(caseId, newRows);
    }

    private static String buildLocationServiceKey(Id caseId, String normalized) {
        return String.valueOf(caseId) + '|' + String.valueOf(normalized);
    }

    @TestVisible
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
                String stateLabel = normalizeStateLabel(parsed.state);
                String stateCode = normalizeStateCode(parsed.state);
                if (!String.isBlank(stateLabel)) {
                    putIfWriteable(ls, fields, 'GNAL_Current_Location__State__s', stateLabel);
                }
                if (!String.isBlank(stateCode)) {
                    putIfWriteable(ls, fields, 'GNAL_Current_Location__StateCode__s', stateCode);
                }
            }
            if (!String.isBlank(parsed.postal)) {
                putIfWriteable(ls, fields, 'GNAL_Current_Location__PostalCode__s', parsed.postal);
            }
            if (!String.isBlank(parsed.country)) {
                String countryLabel = normalizeCountryLabel(parsed.country);
                String countryCode = normalizeCountryCode(parsed.country);
                if (!String.isBlank(countryLabel)) {
                    putIfWriteable(ls, fields, 'GNAL_Current_Location__Country__s', countryLabel);
                }
                if (!String.isBlank(countryCode)) {
                    putIfWriteable(ls, fields, 'GNAL_Current_Location__CountryCode__s', countryCode);
                }
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
        Object v = (populated != null && populated.containsKey(api)) ? populated.get(api) : row.get(api);
        return (v instanceof String) ? (String) v : null;
    }

    private static String getContactStringIfSelected(SObject row, Map<String, Schema.SObjectField> fields, String api) {
        if (row == null || fields == null || String.isBlank(api)) return null;
        if (!fields.containsKey(api)) return null;
        Object v = row.get(api);
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

    @TestVisible
    private static String coalesceStr(Object a, Object b) {
        return coalesceStrList(new List<Object>{ a, b });
    }
    @TestVisible
    private static String coalesceStr(Object a, Object b, Object c, Object d) {
        return coalesceStrList(new List<Object>{ a, b, c, d });
    }
    @TestVisible
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
        return normalizeStateLabel(code);
    }

    private static String stateCodeFromInput(String stateOrCode) {
        return normalizeStateCode(stateOrCode);
    }

    private static String countryLabelFromCode(String code) {
        return normalizeCountryLabel(code);
    }

    private static String countryCodeFromInput(String countryOrCode) {
        return normalizeCountryCode(countryOrCode);
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

    private static String normalizeStateCode(String stateOrCode) {
        if (String.isBlank(stateOrCode)) return null;
        String trimmed = stateOrCode.trim();
        String upper = trimmed.toUpperCase();
        if (STATE_CODE_TO_LABEL != null && STATE_CODE_TO_LABEL.containsKey(upper)) return upper;
        if (STATE_CODE_TO_LABEL != null && STATE_CODE_TO_LABEL.containsKey(trimmed)) return trimmed;
        String key = trimmed.toLowerCase();
        if (STATE_LABEL_TO_CODE != null && STATE_LABEL_TO_CODE.containsKey(key)) {
            return STATE_LABEL_TO_CODE.get(key);
        }
        return null;
    }

    private static String normalizeStateLabel(String stateOrCode) {
        if (String.isBlank(stateOrCode)) return null;
        String trimmed = stateOrCode.trim();
        String code = normalizeStateCode(trimmed);
        if (code != null && STATE_CODE_TO_LABEL != null && STATE_CODE_TO_LABEL.containsKey(code)) {
            return STATE_CODE_TO_LABEL.get(code);
        }
        String key = trimmed.toLowerCase();
        if (STATE_LABEL_TO_CODE != null && STATE_LABEL_TO_CODE.containsKey(key)) {
            return trimmed;
        }
        return null;
    }

    private static String normalizeCountryCode(String countryOrCode) {
        if (String.isBlank(countryOrCode)) return null;
        String trimmed = countryOrCode.trim();
        String upper = trimmed.toUpperCase();
        if (COUNTRY_CODE_TO_LABEL != null && COUNTRY_CODE_TO_LABEL.containsKey(upper)) return upper;
        if (COUNTRY_CODE_TO_LABEL != null && COUNTRY_CODE_TO_LABEL.containsKey(trimmed)) return trimmed;
        String key = trimmed.toLowerCase();
        if (COUNTRY_LABEL_TO_CODE != null && COUNTRY_LABEL_TO_CODE.containsKey(key)) {
            return COUNTRY_LABEL_TO_CODE.get(key);
        }
        if (upper == 'US') return 'US';
        if (trimmed == 'United States') return 'US';
        return null;
    }

    private static String normalizeCountryLabel(String countryOrCode) {
        if (String.isBlank(countryOrCode)) return null;
        String trimmed = countryOrCode.trim();
        String code = normalizeCountryCode(trimmed);
        if (code != null && COUNTRY_CODE_TO_LABEL != null && COUNTRY_CODE_TO_LABEL.containsKey(code)) {
            return COUNTRY_CODE_TO_LABEL.get(code);
        }
        String key = trimmed.toLowerCase();
        if (COUNTRY_LABEL_TO_CODE != null && COUNTRY_LABEL_TO_CODE.containsKey(key)) {
            return trimmed;
        }
        if (trimmed.equalsIgnoreCase('US') || trimmed.equalsIgnoreCase('USA')) return 'United States';
        return null;
    }

    private static Boolean isZipCode(String value) {
        return !String.isBlank(value) && Pattern.matches(ZIP5_REGEX, value.trim());
    }

    private static Boolean isLikelyState(String value) {
        if (String.isBlank(value)) return false;
        String trimmed = value.trim();
        String code = normalizeStateCode(trimmed);
        if (!String.isBlank(code)) return true;
        String key = trimmed.toLowerCase();
        return STATE_LABEL_TO_CODE != null && STATE_LABEL_TO_CODE.containsKey(key);
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

        // Common: street, city, state, postal (no country)
        if (tokens.size() == 4 && isZipCode(tokens[3])) {
            out.street = tokens[0];
            out.city = tokens[1];
            out.state = tokens[2];
            out.postal = tokens[3];
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

        // Less common: street, city, state (no country)
        if (tokens.size() == 3 && isLikelyState(tokens[2])) {
            out.street = tokens[0];
            out.city = tokens[1];
            out.state = tokens[2];
            cacheParsedAddress(cacheKey, out);
            return out;
        }

        // Less common: street, city, postal (no country/state)
        if (tokens.size() == 3 && isZipCode(tokens[2])) {
            out.street = tokens[0];
            out.city = tokens[1];
            out.postal = tokens[2];
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

    private static Boolean isUnableToLockRow(DmlException ex) {
        if (ex == null) return false;
        for (Integer i = 0; i < ex.getNumDml(); i++) {
            if (ex.getDmlStatusCode(i) == 'UNABLE_TO_LOCK_ROW') {
                return true;
            }
        }
        return false;
    }
}
