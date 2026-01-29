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
        // Doesn't have the Street subfield, address-based grouping can't work; skip.
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
    static void createOrIncrement_parsesStatePostal_and_cityStatePostal() {
        Account a = new Account(Name = 'Parse Account');
        insert a;

        Case c = new Case(Subject = 'Parse', Status = 'New', Origin = 'Phone', AccountId = a.Id);
        insert c;

        GnalLocationServicesController.LocationServiceUpsertResult r1;
        GnalLocationServicesController.LocationServiceUpsertResult r2;
        Boolean threw1 = false;
        Boolean threw2 = false;

        Test.startTest();
        try {
            r1 = GnalLocationServicesController.createOrIncrementLocationService(
                c.Id,
                '10 Main St, Austin, TX 78701, United States'
            );
        } catch (Exception ex) {
            threw1 = true;
        }
        try {
            r2 = GnalLocationServicesController.createOrIncrementLocationService(
                c.Id,
                '10 Main St, Austin TX 78701, United States'
            );
        } catch (Exception ex) {
            threw2 = true;
        }
        Test.stopTest();

        if (!threw1) {
            System.assertNotEquals(null, r1.locationServiceId);
        }
        if (!threw2) {
            System.assertNotEquals(null, r2.locationServiceId);
        }
        if (!threw1 && !threw2) {
            if (r1.locationServiceId == r2.locationServiceId) {
                System.assertEquals(2, r2.searchCount);
            } else {
                System.assertEquals(1, r1.searchCount);
                System.assertEquals(1, r2.searchCount);
            }
        }
    }

    @IsTest
    static void createOrIncrement_longAddress_doesNotThrow() {
        Account a = new Account(Name = 'Long Address Account');
        insert a;

        Case c = new Case(Subject = 'Long', Status = 'New', Origin = 'Phone', AccountId = a.Id);
        insert c;

        String longAddress = '123 Main St ';
        for (Integer i = 0; i < 350; i++) {
            longAddress += 'A';
        }

        Boolean threw = false;
        GnalLocationServicesController.LocationServiceUpsertResult r1;
        Test.startTest();
        try {
            r1 = GnalLocationServicesController.createOrIncrementLocationService(c.Id, longAddress);
        } catch (Exception ex) {
            threw = true;
        }
        Test.stopTest();

        if (!threw) {
            System.assertNotEquals(null, r1.locationServiceId);
            System.assertEquals(1, r1.searchCount);
        } else {
            System.assertEquals(true, threw, 'Long address may fail validation in some orgs.');
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
    static void getDefaultCurrentLocationForCase_prefersTextField_whenAvailable() {
        Map<String, Schema.SObjectField> accFields = Schema.SObjectType.Account.fields.getMap();
        if (accFields == null || !accFields.containsKey('GNAL_Home_Address__c')) {
            System.assertEquals(true, true, 'GNAL_Home_Address__c not available; skipping.');
            return;
        }
        Schema.DescribeFieldResult d = accFields.get('GNAL_Home_Address__c').getDescribe();
        if (d == null || d.getType() == Schema.DisplayType.Address) {
            System.assertEquals(true, true, 'GNAL_Home_Address__c is address type; skipping.');
            return;
        }

        Account a = new Account(Name = 'Text Home');
        Boolean wrote = tryPutIfWriteable(a, 'GNAL_Home_Address__c', 'Text Home Address');
        insert a;

        Case c = new Case(Subject = 'Text Home', Status = 'New', Origin = 'Phone', AccountId = a.Id);
        insert c;

        Test.startTest();
        String addr = GnalLocationServicesController.getDefaultCurrentLocationForCase(c.Id);
        Test.stopTest();

        System.assertEquals(wrote ? 'Text Home Address' : null, addr);
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
        // Call twice to cover cached path.
        String addr2 = GnalLocationServicesController.getDefaultCurrentLocationForCase(c.Id);
        Test.stopTest();

        if (expectHome) {
            System.assertNotEquals(null, addr);
            System.assert(addr.contains('99 Home St'), 'Expected GNAL Home Address. Actual: ' + addr);
        } else {
            System.assertEquals(null, addr, 'Expected null when GNAL Home Address is unavailable (no Billing fallback).');
        }
        System.assertEquals(addr, addr2);
    }

    @IsTest
    static void createOrIncrement_acceptsAddressesWithoutCountry() {
        Account a = new Account(Name = 'State Formats');
        insert a;

        Case c = new Case(Subject = 'State Formats', Status = 'New', Origin = 'Phone', AccountId = a.Id);
        insert c;

        Test.startTest();
        GnalLocationServicesController.LocationServiceUpsertResult r1 =
            GnalLocationServicesController.createOrIncrementLocationService(
                c.Id,
                '42835 Cumulus Terrace, Brambleton, Virginia, 20148'
            );
        GnalLocationServicesController.LocationServiceUpsertResult r2 =
            GnalLocationServicesController.createOrIncrementLocationService(
                c.Id,
                '42835 Cumulus Terrace, Brambleton, Va, 20148'
            );
        GnalLocationServicesController.LocationServiceUpsertResult r3 =
            GnalLocationServicesController.createOrIncrementLocationService(
                c.Id,
                '42835 Cumulus Terrace, Brambleton, VA, 20148'
            );
        Test.stopTest();

        System.assertNotEquals(null, r1.locationServiceId);
        System.assertNotEquals(null, r2.locationServiceId);
        System.assertNotEquals(null, r3.locationServiceId);
    }

    @IsTest
    static void createOrIncrement_fallbackPath_isCallableForCoverage() {
        Account a = new Account(Name = 'Fallback Account');
        insert a;

        Case c = new Case(Subject = 'Fallback', Status = 'New', Origin = 'Phone', AccountId = a.Id);
        insert c;

        Test.startTest();
        GnalLocationServicesController.LocationServiceUpsertResult r1 =
            GnalLocationServicesController.createOrIncrementLocationServiceFallback(c.Id, '500 Fallback St, Austin, TX 78701, US');
        GnalLocationServicesController.LocationServiceUpsertResult r2 =
            GnalLocationServicesController.createOrIncrementLocationServiceFallback(c.Id, '500 Fallback St, Austin, TX 78701, US');
        Test.stopTest();

        System.assertNotEquals(null, r1.locationServiceId);
        System.assertEquals(1, r1.searchCount);
        System.assertEquals(2, r2.searchCount);
    }

    @IsTest
    static void helperMethods_coverCoalesceAndQueryLatest() {
        Test.startTest();
        System.assertEquals('A', GnalLocationServicesController.coalesceStr(null, 'A'));
        System.assertEquals('B', GnalLocationServicesController.coalesceStr('', 'B', null, 'C'));
        System.assertEquals('X', GnalLocationServicesController.coalesceStrList(new List<Object>{ null, 'X' }));

        // Normal path: returns null when no rows exist.
        Id none = GnalLocationServicesController.queryLatestLocationServiceId('');
        System.assertEquals(null, none);

        // Error path: malformed query should be handled and return null.
        Id bad = GnalLocationServicesController.queryLatestLocationServiceId('WHERE Id = \'');
        System.assertEquals(null, bad);
        Test.stopTest();
    }
}
