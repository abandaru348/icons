@IsTest
private class GnalFacilitySearchControllerAdditionalTest {

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
    static void getCaseBillingAddress_returnsBillingAddress() {
        Account a = new Account(
            Name = 'Billing Acct',
            BillingStreet = '500 Main St',
            BillingCity = 'Austin',
            BillingPostalCode = '78701'
        );
        // Prefer codes where org uses state/country picklists.
        setFieldIfExists(a, 'BillingStateCode', 'TX');
        setFieldIfExists(a, 'BillingCountryCode', 'US');
        // Some orgs still allow BillingCountry as text.
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
        GeocodeCache__c cache = new GeocodeCache__c(
            Name = 'MilesOnly',
            Origin_Address__c = originAddress,
            Destination_Address__c = destAddress,
            Distance_Miles__c = 3,
            Distance_Meters__c = 4828,
            Travel_Time_Minutes__c = 12
        );
        insert cache;

        Test.startTest();
        List<Map<String, Object>> results =
            GnalFacilitySearchController.findNearestFacilitiesWithRadius(null, originAddress, 5);
        Test.stopTest();

        System.assertNotEquals(null, results);
        System.assertEquals(true, results.size() >= 1, 'Expected miles-only fallback results in tests.');
    }

    @IsTest
    static void findNearestFacilitiesWithRadius_parentTerritoryDedup_doesNotThrow() {
        // This test is mainly to execute getDistinctTerritories() + addTerritoryIfNew() duplicate path
        // where multiple children point at the same parent territory.
        OperatingHours oh = new OperatingHours(Name = 'OH Parent', TimeZone = 'America/Chicago');
        insert oh;

        ServiceTerritory parent = new ServiceTerritory(
            Name = 'Parent Facility',
            IsActive = true,
            OperatingHoursId = oh.Id,
            Street = '10 Parent St',
            City = 'Austin',
            PostalCode = '78701'
        );
        insert parent;

        ServiceTerritory child1 = new ServiceTerritory(
            Name = 'Child 1',
            IsActive = true,
            OperatingHoursId = oh.Id,
            ParentTerritoryId = parent.Id,
            Street = '11 Child St',
            City = 'Austin',
            PostalCode = '78701'
        );
        ServiceTerritory child2 = new ServiceTerritory(
            Name = 'Child 2',
            IsActive = true,
            OperatingHoursId = oh.Id,
            ParentTerritoryId = parent.Id,
            Street = '12 Child St',
            City = 'Austin',
            PostalCode = '78701'
        );
        insert new List<ServiceTerritory>{ child1, child2 };

        String originAddress = '100 Origin St, Austin, TX 78701';
        String parentDest = formatAddress(parent.Street, parent.City, null, parent.PostalCode, null);

        // Cache row for the parent destination (destinationAddressSet will include the parent).
        insert new GeocodeCache__c(
            Name = 'ParentCache',
            Origin_Address__c = originAddress,
            Destination_Address__c = parentDest,
            Distance_Miles__c = 2,
            Distance_Meters__c = 3218,
            Travel_Time_Minutes__c = 8
        );

        Test.startTest();
        List<Map<String, Object>> results =
            GnalFacilitySearchController.findNearestFacilitiesWithRadius(null, originAddress, 50);
        Test.stopTest();

        System.assertNotEquals(null, results);
    }
}

