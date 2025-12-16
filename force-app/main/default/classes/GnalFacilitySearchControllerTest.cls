@IsTest
private class GnalFacilitySearchControllerTest {
    private static void setGeo(SObject record, String fieldApiName, Double lat, Double lon) {
        if (record == null || String.isBlank(fieldApiName) || lat == null || lon == null) return;
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.GeocodeCache__c.fields.getMap();
        if (fields == null) return;

        Schema.SObjectField f = fields.get(fieldApiName);
        if (f != null && f.getDescribe().isCreateable()) {
            record.put(fieldApiName, Location.newInstance(lat, lon));
            return;
        }

        if (fieldApiName.endsWith('__c')) {
            String latField = fieldApiName.substring(0, fieldApiName.length() - 3) + '__Latitude__s';
            String lonField = fieldApiName.substring(0, fieldApiName.length() - 3) + '__Longitude__s';
            Schema.SObjectField lf = fields.get(latField);
            Schema.SObjectField lof = fields.get(lonField);
            if (lf != null && lf.getDescribe().isCreateable()) record.put(latField, lat);
            if (lof != null && lof.getDescribe().isCreateable()) record.put(lonField, lon);
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
    static void getAccountBillingAddress_returnsJoinedAddress() {
        Account a = new Account(
            Name = 'Test Account',
            BillingStreet = '123 Main St',
            BillingCity = 'Austin',
            BillingState = 'TX',
            BillingPostalCode = '78701',
            BillingCountry = 'USA'
        );
        insert a;

        Test.startTest();
        String result = GnalFacilitySearchController.getAccountBillingAddress(a.Id);
        Test.stopTest();

        System.assertEquals('123 Main St, Austin, TX, 78701, USA', result);
    }

    @IsTest
    static void getAccountBillingAddress_nullAccount_returnsNull() {
        Test.startTest();
        String result = GnalFacilitySearchController.getAccountBillingAddress(null);
        Test.stopTest();

        System.assertEquals(null, result);
    }

    @IsTest
    static void getLatestCaseOriginAddress_internalUserWithoutAccount_returnsNull() {
        // Most internal users do not have User.AccountId populated.
        // The controller should safely return null rather than throwing.
        Test.startTest();
        String origin = GnalFacilitySearchController.getLatestCaseOriginAddress();
        Test.stopTest();

        System.assertEquals(null, origin);
    }

    @IsTest
    static void getLatestCaseOriginAddressForAccount_noCases_returnsNull() {
        Account a = new Account(Name = 'No Case Account');
        insert a;

        Test.startTest();
        String origin = GnalFacilitySearchController.getLatestCaseOriginAddressForAccount(a.Id);
        Test.stopTest();

        System.assertEquals(null, origin);
    }

    @IsTest
    static void getLatestCaseOriginAddressForAccount_prefersStrictMatch() {
        Account a = new Account(Name = 'Case Account');
        insert a;

        // Fallback-eligible case (GNAL populated but Origin/Status not the strict values)
        Case cFallback = new Case(
            AccountId = a.Id,
            Origin = 'Email',
            Status = 'Working',
            GNAL_Origin_Location__c = 'Fallback Address'
        );
        insert cFallback;

        // Strict match case (should win even if older/newer ordering differs by CreatedDate)
        Case cStrict = new Case(
            AccountId = a.Id,
            Origin = 'Phone',
            Status = 'New',
            GNAL_Origin_Location__c = 'Strict Address'
        );
        insert cStrict;

        Test.startTest();
        String origin = GnalFacilitySearchController.getLatestCaseOriginAddressForAccount(a.Id);
        Test.stopTest();

        System.assertEquals('Strict Address', origin);
    }

    @IsTest
    static void getLatestCaseOriginAddressForAccount_fallbacksWhenPicklistsDiffer() {
        Account a = new Account(Name = 'Case Fallback Account');
        insert a;

        // No strict match, but GNAL origin is populated.
        Case c = new Case(
            AccountId = a.Id,
            Origin = 'Web',
            Status = 'Closed',
            GNAL_Origin_Location__c = 'Only Available Address'
        );
        insert c;

        Test.startTest();
        String origin = GnalFacilitySearchController.getLatestCaseOriginAddressForAccount(a.Id);
        Test.stopTest();

        System.assertEquals('Only Available Address', origin);
    }

    @IsTest
    static void findNearestFacilitiesWithRadius_cacheHit_returnsResults() {
        // Create a facility (ServiceTerritory) with an address.
        // Note: ServiceTerritory exists in orgs with Field Service; if unavailable, this test will need org support.
        ServiceTerritory st = new ServiceTerritory(
            Name = 'Facility A',
            IsActive = true,
            Street = '1 Facility Way',
            City = 'Austin',
            State = 'TX',
            PostalCode = '78701',
            Country = 'USA'
        );
        insert st;

        String destAddress = formatAddress(st.Street, st.City, st.State, st.PostalCode, st.Country);
        String originAddress = '100 Origin St, Austin, TX 78701';

        // Insert a cache row that matches (origin, destination) so the controller does NOT call Google.
        GeocodeCache__c cache = new GeocodeCache__c();
        cache.Name = 'Cache-1';
        cache.Origin_Address__c = originAddress;
        cache.Destination_Address__c = destAddress;
        cache.Distance_Miles__c = 3;
        cache.Distance_Meters__c = 4828;
        cache.Travel_Time_Minutes__c = 12;

        // Populate destination location used by DISTANCE().
        setGeo(cache, 'Destination_Location__c', 30.2672, -97.7431);
        // Populate origin location so controller can build originLocation without calling Google.
        // Prefer Origin_Location__c if it exists; otherwise use whatever origin geolocation fields are present.
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.GeocodeCache__c.fields.getMap();
        if (fields != null && fields.containsKey('Origin_Location__c')) {
            setGeo(cache, 'Origin_Location__c', 30.2672, -97.7431);
        } else if (fields != null && fields.containsKey('Origin_Location_Latitude__c')) {
            // In some orgs these were created as (redundant) geolocation fields; set the point.
            setGeo(cache, 'Origin_Location_Latitude__c', 30.2672, -97.7431);
        }

        insert cache;

        Test.startTest();
        List<Map<String, Object>> results =
            GnalFacilitySearchController.findNearestFacilitiesWithRadius(null, originAddress, 5);
        Test.stopTest();

        System.assertNotEquals(null, results);
        System.assertEquals(true, results.size() >= 1, 'Should return at least one cached facility');
    }

    @IsTest
    static void findNearestFacilitiesWithRadius_blankOrigin_throws() {
        try {
            Test.startTest();
            GnalFacilitySearchController.findNearestFacilitiesWithRadius(null, null, 5);
            Test.stopTest();
            System.assert(false, 'Expected AuraHandledException');
        } catch (Exception ex) {
            System.assert(String.valueOf(ex.getMessage()).contains('Origin address is required'));
        }
    }
}
