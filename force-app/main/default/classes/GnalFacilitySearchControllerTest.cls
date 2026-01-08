@IsTest
private class GnalFacilitySearchControllerTest {
    private static void setFieldIfExists(SObject record, String fieldApiName, Object value) {
        if (record == null || String.isBlank(fieldApiName)) return;
        Map<String, Schema.SObjectField> fields = record.getSObjectType().getDescribe().fields.getMap();
        if (fields != null && fields.containsKey(fieldApiName)) {
            record.put(fieldApiName, value);
        }
    }

    private static String formatAddress(String street, String city, String state, String postal, String country) {
        List<String> parts = new List<String>();
        if (!String.isBlank(street)) parts.add(street);
        if (!String.isBlank(city)) parts.add(city);
        if (!String.isBlank(state)) parts.add(state);
        if (!String.isBlank(postal)) parts.add(postal);
        if (!String.isBlank(country)) parts.add(country);
        return String.join(parts, ', ');
    }

    @IsTest
    static void getCaseAccountId_nullCaseId_returnsNull() {
        Test.startTest();
        Id out = GnalFacilitySearchController.getCaseAccountId(null);
        Test.stopTest();
        System.assertEquals(null, out);
    }

    @IsTest
    static void getCaseAccountId_returnsAccountId() {
        Account a = new Account(Name = 'Acct');
        insert a;
        Case c = new Case(Subject = 'Test', Status = 'New', Origin = 'Phone', AccountId = a.Id);
        insert c;

        Test.startTest();
        Id out = GnalFacilitySearchController.getCaseAccountId(c.Id);
        Test.stopTest();

        System.assertEquals(a.Id, out);
    }

    @IsTest
    static void getCaseBillingAddress_nullCaseId_returnsNull() {
        Test.startTest();
        String addr = GnalFacilitySearchController.getCaseBillingAddress(null);
        Test.stopTest();
        System.assertEquals(null, addr);
    }

    @IsTest
    static void getCaseBillingAddress_caseWithNoAccount_returnsNull() {
        Case c = new Case(Subject = 'No Account', Status = 'New', Origin = 'Phone');
        insert c;

        Test.startTest();
        String addr = GnalFacilitySearchController.getCaseBillingAddress(c.Id);
        Test.stopTest();
        System.assertEquals(null, addr);
    }

    @IsTest
    static void getCaseBillingAddress_returnsBillingAddress() {
        Account a = new Account(
            Name = 'Billing Acct',
            BillingStreet = '500 Main St',
            BillingCity = 'Austin',
            BillingPostalCode = '78701'
        );
        setFieldIfExists(a, 'BillingStateCode', 'TX');
        setFieldIfExists(a, 'BillingCountryCode', 'US');
        setFieldIfExists(a, 'BillingCountry', 'United States');
        insert a;

        Case c = new Case(Subject = 'Test', Status = 'New', Origin = 'Phone', AccountId = a.Id);
        insert c;

        Test.startTest();
        String addr = GnalFacilitySearchController.getCaseBillingAddress(c.Id);
        Test.stopTest();

        System.assertNotEquals(null, addr);
        System.assert(addr.contains('500 Main St'), 'Expected street in billing address. Actual: ' + addr);
        System.assert(addr.contains('Austin'), 'Expected city in billing address. Actual: ' + addr);
    }

    @IsTest
    static void findFacilitiesFromCacheWithRadius_noCacheRows_returnsEmpty_inTests() {
        Test.startTest();
        List<Map<String, Object>> results = GnalFacilitySearchController.findFacilitiesFromCacheWithRadius('No Cache Origin', 10);
        Test.stopTest();
        System.assertNotEquals(null, results);
        System.assertEquals(0, results.size());
    }

    @IsTest
    static void findFacilitiesFromCacheWithRadius_trimsOriginAddress_inTests() {
        String origin = 'Trim Me';
        insert new GeocodeCache__c(
            Name = 'TrimCache',
            Origin_Address__c = origin,
            Destination_Address__c = 'Dest',
            Distance_Miles__c = 1,
            Distance_Meters__c = 1609,
            Travel_Time_Minutes__c = 5
        );

        Test.startTest();
        List<Map<String, Object>> results = GnalFacilitySearchController.findFacilitiesFromCacheWithRadius('  ' + origin + '  ', 5);
        Test.stopTest();

        System.assertNotEquals(null, results);
        System.assertEquals(true, results.size() >= 1);
    }

    @IsTest
    static void findNearestFacilitiesWithRadius_fallsBackToMilesOnlyWhenOriginCoordsMissingInTests() {
        // Create a facility (ServiceTerritory) with an address.
        OperatingHours oh = new OperatingHours(Name = 'OH', TimeZone = 'America/Chicago');
        insert oh;

        ServiceTerritory st = new ServiceTerritory(
            Name = 'Facility Fallback',
            IsActive = true,
            OperatingHoursId = oh.Id,
            Street = '1 Facility Way',
            City = 'Austin',
            PostalCode = '78701'
        );
        setFieldIfExists(st, 'CountryCode', 'US');
        setFieldIfExists(st, 'StateCode', 'TX');
        insert st;

        String destAddress = formatAddress(st.Street, st.City, null, st.PostalCode, null);
        String originAddress = '100 Origin St, Austin, TX 78701';

        // Insert cache row WITHOUT any origin coordinates; in tests the controller should fall back to Distance_Miles__c.
        insert new GeocodeCache__c(
            Name = 'MilesOnly',
            Origin_Address__c = originAddress,
            Destination_Address__c = destAddress,
            Distance_Miles__c = 3,
            Distance_Meters__c = 4828,
            Travel_Time_Minutes__c = 12
        );

        Test.startTest();
        List<Map<String, Object>> results =
            GnalFacilitySearchController.findNearestFacilitiesWithRadius(null, originAddress, 5);
        Test.stopTest();

        System.assertNotEquals(null, results);
        System.assertEquals(true, results.size() >= 1, 'Expected miles-only fallback results in tests.');
    }

    @IsTest
    static void getLatestCaseOriginAddressForAccount_formatsFromSubfields_whenPresent() {
        Account a = new Account(Name = 'Origin Format Acct');
        insert a;

        Case c = new Case(AccountId = a.Id, Origin = 'Phone', Status = 'New', Subject = 'Origin');
        Map<String, Schema.SObjectField> caseFields = Schema.SObjectType.Case.fields.getMap();
        Boolean wroteAny = false;
        if (caseFields != null && caseFields.containsKey('GNAL_Origin_Location__Street__s')) {
            c.put('GNAL_Origin_Location__Street__s', '10 Street');
            wroteAny = true;
        }
        if (caseFields != null && caseFields.containsKey('GNAL_Origin_Location__City__s')) {
            c.put('GNAL_Origin_Location__City__s', 'Austin');
            wroteAny = true;
        }
        if (caseFields != null && caseFields.containsKey('GNAL_Origin_Location__State__s')) {
            c.put('GNAL_Origin_Location__State__s', 'TX');
            wroteAny = true;
        }
        if (caseFields != null && caseFields.containsKey('GNAL_Origin_Location__PostalCode__s')) {
            c.put('GNAL_Origin_Location__PostalCode__s', '78701');
            wroteAny = true;
        }
        if (caseFields != null && caseFields.containsKey('GNAL_Origin_Location__Country__s')) {
            c.put('GNAL_Origin_Location__Country__s', 'US');
            wroteAny = true;
        }
        insert c;

        Test.startTest();
        String origin = GnalFacilitySearchController.getLatestCaseOriginAddressForAccount(a.Id);
        Test.stopTest();

        if (wroteAny) {
            System.assertNotEquals(null, origin);
            System.assert(origin.contains('10 Street'));
        } else {
            System.assertEquals(null, origin);
        }
    }
}

