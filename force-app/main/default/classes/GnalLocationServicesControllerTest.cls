@IsTest
private class GnalLocationServicesControllerTest {

    private static Boolean tryPutIfWriteable(SObject record, String fieldApiName, Object value) {
        try {
            if (record == null || String.isBlank(fieldApiName) || value == null) return false;
            Map<String, Schema.SObjectField> fields = record.getSObjectType().getDescribe().fields.getMap();
            if (fields == null || !fields.containsKey(fieldApiName)) return false;

            Schema.DescribeFieldResult d = fields.get(fieldApiName).getDescribe();
            if (d == null || !(d.isCreateable() || d.isUpdateable())) return false;

            record.put(fieldApiName, value);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    private static Id getPersonAccountRecordTypeId() {
        try {
            // Only works when Person Accounts are enabled.
            RecordType rt = [
                SELECT Id
                FROM RecordType
                WHERE SObjectType = 'Account'
                AND IsPersonType = true
                LIMIT 1
            ];
            return rt.Id;
        } catch (Exception e) {
            return null;
        }
    }

    private static GNAL_Location_Service__c queryLocationService(Id locationServiceId) {
        if (locationServiceId == null) return null;

        Map<String, Schema.SObjectField> fields = Schema.SObjectType.GNAL_Location_Service__c.fields.getMap();
        List<String> selectFields = new List<String>{ 'Id', 'GNAL_Search_Count__c', 'GNAL_Case__c' };
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
            if (fields != null && fields.containsKey(f)) selectFields.add(f);
        }

        String soql =
            'SELECT ' + String.join(selectFields, ',') +
            ' FROM GNAL_Location_Service__c' +
            ' WHERE Id = \'' + String.escapeSingleQuotes(String.valueOf(locationServiceId)) + '\'' +
            ' LIMIT 1';
        return (GNAL_Location_Service__c) Database.query(soql);
    }

    @IsTest
    static void createOrIncrement_createsOnceAndIncrements_andNormalizes() {
        Account a = new Account(Name = 'Test Account');
        insert a;

        Case c = new Case(Subject = 'Test', Status = 'New', Origin = 'Phone', AccountId = a.Id);
        insert c;

        Test.startTest();
        GnalLocationServicesController.LocationServiceUpsertResult r1 =
            GnalLocationServicesController.createOrIncrementLocationService(c.Id, '  123  Main   St  ');
        GnalLocationServicesController.LocationServiceUpsertResult r2 =
            GnalLocationServicesController.createOrIncrementLocationService(c.Id, '123 Main St');
        Test.stopTest();

        System.assertNotEquals(null, r1.locationServiceId);
        System.assertEquals(r1.locationServiceId, r2.locationServiceId);
        System.assertEquals(1, r1.searchCount);
        System.assertEquals(2, r2.searchCount);
        System.assertEquals('123 Main St', r1.currentLocation);

        GNAL_Location_Service__c saved = [
            SELECT Id, GNAL_Case__c, GNAL_Search_Count__c
            FROM GNAL_Location_Service__c
            WHERE Id = :r1.locationServiceId
            LIMIT 1
        ];
        System.assertEquals(c.Id, saved.GNAL_Case__c);
        System.assertEquals(2, Integer.valueOf(saved.GNAL_Search_Count__c));
    }

    @IsTest
    static void createOrIncrement_createsNewRecordWhenAddressChanges_andReusesPerAddress() {
        // If the org doesn't have the Street subfield, address-based grouping can't work; skip.
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.GNAL_Location_Service__c.fields.getMap();
        if (fields == null || !fields.containsKey('GNAL_Current_Location__Street__s')) {
            System.assertEquals(true, true, 'Org does not have GNAL_Current_Location__Street__s; skipping.');
            return;
        }

        Account a = new Account(Name = 'Test Account Address Change');
        insert a;

        Case c = new Case(Subject = 'Test', Status = 'New', Origin = 'Phone', AccountId = a.Id);
        insert c;

        Test.startTest();
        GnalLocationServicesController.LocationServiceUpsertResult r1 =
            GnalLocationServicesController.createOrIncrementLocationService(c.Id, '123 Main St, Austin, TX, 78701, United States');
        GnalLocationServicesController.LocationServiceUpsertResult r2 =
            GnalLocationServicesController.createOrIncrementLocationService(c.Id, '999 Other St, Austin, TX, 78702, United States');
        // Same as r2 address -> increment that record
        GnalLocationServicesController.LocationServiceUpsertResult r3 =
            GnalLocationServicesController.createOrIncrementLocationService(c.Id, '  999  Other St,  Austin, TX, 78702, United States  ');
        // Back to r1 address -> increment the original record (not create a 3rd)
        GnalLocationServicesController.LocationServiceUpsertResult r4 =
            GnalLocationServicesController.createOrIncrementLocationService(c.Id, '123 Main St, Austin, TX, 78701, United States');
        Test.stopTest();

        System.assertNotEquals(null, r1.locationServiceId);
        System.assertNotEquals(null, r2.locationServiceId);
        System.assertNotEquals(r1.locationServiceId, r2.locationServiceId, 'Expected a new record when address changes');

        System.assertEquals(r2.locationServiceId, r3.locationServiceId, 'Expected same-address searches to reuse same record');
        System.assertEquals(2, r3.searchCount, 'Expected search count increment for same address');

        System.assertEquals(r1.locationServiceId, r4.locationServiceId, 'Expected original address to reuse original record');
        System.assertEquals(2, r4.searchCount, 'Expected search count increment for original address');
    }

    @IsTest
    static void createOrIncrement_parsesFourTokenStatePostalAndCountryCode() {
        Account a = new Account(Name = 'Parse 4-token');
        insert a;
        Case c = new Case(Subject = 'Test', Status = 'New', Origin = 'Phone', AccountId = a.Id);
        insert c;

        // 4 tokens: street, city, "state postal", countryCode
        String addr = '1 Test St, Austin, TX 78701, US';

        Test.startTest();
        GnalLocationServicesController.LocationServiceUpsertResult r1 =
            GnalLocationServicesController.createOrIncrementLocationService(c.Id, addr);
        GnalLocationServicesController.LocationServiceUpsertResult r2 =
            GnalLocationServicesController.createOrIncrementLocationService(c.Id, addr);
        Test.stopTest();

        System.assertEquals(r1.locationServiceId, r2.locationServiceId);
        System.assertEquals(2, r2.searchCount);

        GNAL_Location_Service__c saved = queryLocationService(r1.locationServiceId);
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.GNAL_Location_Service__c.fields.getMap();
        if (fields != null && fields.containsKey('GNAL_Current_Location__StateCode__s')) {
            System.assertEquals('TX', (String) saved.get('GNAL_Current_Location__StateCode__s'));
        }
        if (fields != null && fields.containsKey('GNAL_Current_Location__CountryCode__s')) {
            System.assertEquals('US', (String) saved.get('GNAL_Current_Location__CountryCode__s'));
        }
    }

    @IsTest
    static void createOrIncrement_parsesThreeTokenCityStatePostal() {
        Account a = new Account(Name = 'Parse 3-token');
        insert a;
        Case c = new Case(Subject = 'Test', Status = 'New', Origin = 'Phone', AccountId = a.Id);
        insert c;

        // 3 tokens: street, "city state postal", countryCode
        String addr = '2 Test St, Austin TX 78701, US';

        Test.startTest();
        GnalLocationServicesController.LocationServiceUpsertResult r1 =
            GnalLocationServicesController.createOrIncrementLocationService(c.Id, addr);
        Test.stopTest();

        System.assertNotEquals(null, r1.locationServiceId);
        GNAL_Location_Service__c saved = queryLocationService(r1.locationServiceId);
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.GNAL_Location_Service__c.fields.getMap();
        if (fields != null && fields.containsKey('GNAL_Current_Location__City__s')) {
            System.assertEquals('Austin', (String) saved.get('GNAL_Current_Location__City__s'));
        }
        if (fields != null && fields.containsKey('GNAL_Current_Location__PostalCode__s')) {
            System.assertEquals('78701', (String) saved.get('GNAL_Current_Location__PostalCode__s'));
        }
        if (fields != null && fields.containsKey('GNAL_Current_Location__CountryCode__s')) {
            System.assertEquals('US', (String) saved.get('GNAL_Current_Location__CountryCode__s'));
        }
    }

    @IsTest
    static void createOrIncrement_convertsStateAndCountryLabelsToCodes() {
        Account a = new Account(Name = 'Label->Code');
        insert a;
        Case c = new Case(Subject = 'Test', Status = 'New', Origin = 'Phone', AccountId = a.Id);
        insert c;

        // 5 tokens: street, city, stateLabel, postal, countryLabel
        // This is expected to populate StateCode__s/CountryCode__s via label->code mapping.
        String addr = '3 Test St, Austin, Texas, 78701, United States';

        Test.startTest();
        GnalLocationServicesController.LocationServiceUpsertResult r1 =
            GnalLocationServicesController.createOrIncrementLocationService(c.Id, addr);
        Test.stopTest();

        GNAL_Location_Service__c saved = queryLocationService(r1.locationServiceId);
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.GNAL_Location_Service__c.fields.getMap();
        if (fields != null && fields.containsKey('GNAL_Current_Location__StateCode__s')) {
            System.assertEquals('TX', (String) saved.get('GNAL_Current_Location__StateCode__s'));
        }
        if (fields != null && fields.containsKey('GNAL_Current_Location__CountryCode__s')) {
            System.assertEquals('US', (String) saved.get('GNAL_Current_Location__CountryCode__s'));
        }
    }

    @IsTest
    static void getDefaultCurrentLocationForCase_convertsHomeStateAndCountryCodesToLabels() {
        // Cover the branch where Home Address only has codes; controller should return labels when possible.
        Id personRtId = getPersonAccountRecordTypeId();
        if (personRtId == null) {
            System.assertEquals(true, true, 'Person Accounts not enabled; skipping label conversion test.');
            return;
        }

        Account a = new Account(RecordTypeId = personRtId, LastName = 'PA Codes');
        Boolean wroteAny =
            tryPutIfWriteable(a, 'GNAL_Home_Address__Street__s', '10 Code St') |
            tryPutIfWriteable(a, 'GNAL_Home_Address__City__s', 'Austin') |
            tryPutIfWriteable(a, 'GNAL_Home_Address__StateCode__s', 'TX') |
            tryPutIfWriteable(a, 'GNAL_Home_Address__PostalCode__s', '78701') |
            tryPutIfWriteable(a, 'GNAL_Home_Address__CountryCode__s', 'US');
        insert a;

        Case c = new Case(Subject = 'Has Account', Status = 'New', Origin = 'Phone', AccountId = a.Id);
        insert c;

        Test.startTest();
        String addr = GnalLocationServicesController.getDefaultCurrentLocationForCase(c.Id);
        Test.stopTest();

        if (wroteAny) {
            System.assertNotEquals(null, addr);
            System.assert(addr.contains('10 Code St'));
            // State/Country should be labels when picklists are enabled and available.
            System.assertEquals(false, addr.contains(', TX,'), 'Expected state label rather than code. Actual: ' + addr);
            System.assertEquals(false, addr.endsWith(', US'), 'Expected country label rather than code. Actual: ' + addr);
        } else {
            System.assertEquals(null, addr, 'Expected null when home address fields are unavailable/unwriteable.');
        }
    }

    @IsTest
    static void createOrIncrement_requiresCaseId() {
        Boolean threw = false;
        try {
            Test.startTest();
            GnalLocationServicesController.createOrIncrementLocationService(null, '123 Main St');
        } catch (Exception ex) {
            threw = true;
        } finally {
            Test.stopTest();
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void createOrIncrement_requiresCurrentLocation() {
        Account a = new Account(Name = 'Test Account 2');
        insert a;

        Case c = new Case(Subject = 'Test', Status = 'New', Origin = 'Phone', AccountId = a.Id);
        insert c;

        Boolean threw = false;
        try {
            Test.startTest();
            GnalLocationServicesController.createOrIncrementLocationService(c.Id, '   ');
        } catch (Exception ex) {
            threw = true;
        } finally {
            Test.stopTest();
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void getDefaultCurrentLocationForCase_nullCaseId_returnsNull() {
        Test.startTest();
        String addr = GnalLocationServicesController.getDefaultCurrentLocationForCase(null);
        Test.stopTest();
        System.assertEquals(null, addr);
    }

    @IsTest
    static void getDefaultCurrentLocationForCase_returnsNullWhenNoAccount() {
        Case c = new Case(Subject = 'No Account', Status = 'New', Origin = 'Phone');
        insert c;

        Test.startTest();
        String addr = GnalLocationServicesController.getDefaultCurrentLocationForCase(c.Id);
        Test.stopTest();

        System.assertEquals(null, addr);
    }

    @IsTest
    static void getDefaultCurrentLocationForCase_usesHomeAddressOnly_noBillingFallback() {
        Id personRtId = getPersonAccountRecordTypeId();

        Account a;
        Boolean expectHome = false;

        if (personRtId != null) {
            // Person Account path (often required for home-address style fields)
            a = new Account(
                RecordTypeId = personRtId,
                LastName = 'PA Test'
            );

            // Try to set GNAL home address subfields (Address compound).
            Boolean wroteAny =
                tryPutIfWriteable(a, 'GNAL_Home_Address__Street__s', '99 Home St') |
                tryPutIfWriteable(a, 'GNAL_Home_Address__City__s', 'Dallas') |
                tryPutIfWriteable(a, 'GNAL_Home_Address__State__s', 'TX') |
                tryPutIfWriteable(a, 'GNAL_Home_Address__PostalCode__s', '75001') |
                tryPutIfWriteable(a, 'GNAL_Home_Address__Country__s', 'US');

            expectHome = wroteAny;
        } else {
            // Business Account fallback
            a = new Account(Name = 'Business Account');
        }

        // Billing fields should NOT affect the returned current location anymore.
        a.BillingStreet = '10 Billing St';
        a.BillingCity = 'Austin';
        a.BillingPostalCode = '78701';
        tryPutIfWriteable(a, 'BillingStateCode', 'TX');
        tryPutIfWriteable(a, 'BillingCountryCode', 'US');

        insert a;

        Case c = new Case(Subject = 'Has Account', Status = 'New', Origin = 'Phone', AccountId = a.Id);
        insert c;

        Test.startTest();
        String addr = GnalLocationServicesController.getDefaultCurrentLocationForCase(c.Id);
        Test.stopTest();

        if (expectHome) {
            System.assertNotEquals(null, addr);
            System.assert(addr.contains('99 Home St'), 'Expected GNAL Home Address. Actual: ' + addr);
        } else {
            System.assertEquals(null, addr, 'Expected null when GNAL Home Address is unavailable (no Billing fallback).');
        }
    }
}

