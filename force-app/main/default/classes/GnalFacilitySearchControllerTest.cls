@isTest
private class GnalFacilitySearchControllerTest {

    private class MockCallout implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);

            if (req.getEndpoint() != null && req.getEndpoint().contains('geocode')) {
                res.setBody('{"results":[{"geometry":{"location":{"lat":10.0,"lng":20.0}}}],"status":"OK"}');
            } else {
                res.setBody('[{"destinationIndex":0,"duration":"100s","distanceMeters":5000},'
                            + '{"destinationIndex":1,"duration":"200s","distanceMeters":7000}]');
            }
            return res;
        }
    }

    @isTest
    static void testFindNearestFacilities() {
        Account acc = new Account(
            Name = 'Test Account',
            BillingStreet = '123 Billing St',
            BillingCity = 'Billing City',
            BillingState = 'CA',
            BillingPostalCode = '90210',
            BillingCountry = 'USA'
        );
        insert acc;

        OperatingHours hours = new OperatingHours(
            Name = 'Default Hours',
            TimeZone = 'America/Los_Angeles'
        );
        insert hours;

        ServiceTerritory territoryA = new ServiceTerritory(
            Name = 'Territory A',
            IsActive = true,
            Street = '123 A St',
            City = 'City A',
            State = 'CA',
            PostalCode = '90001',
            Country = 'USA',
            OperatingHoursId = hours.Id
        );
        insert territoryA;

        insert new ServiceTerritory(
            Name = 'Territory B',
            IsActive = true,
            Street = '456 B St',
            City = 'City B',
            State = 'CA',
            PostalCode = '90002',
            Country = 'USA',
            OperatingHoursId = hours.Id
        );

        insert new ServiceTerritory(
            Name = 'Territory A - Child',
            IsActive = true,
            Street = '789 Child St',
            City = 'City C',
            State = 'CA',
            PostalCode = '90003',
            Country = 'USA',
            ParentTerritoryId = territoryA.Id,
            OperatingHoursId = hours.Id
        );

        insert new ServiceTerritory(
            Name = 'Territory A - Child 2',
            IsActive = true,
            Street = '101 Child Two St',
            City = 'City D',
            State = 'CA',
            PostalCode = '90004',
            Country = 'USA',
            ParentTerritoryId = territoryA.Id,
            OperatingHoursId = hours.Id
        );

        Test.setMock(HttpCalloutMock.class, new MockCallout());

        Test.startTest();
        List<Map<String, Object>> results = GnalFacilitySearchController.findNearestFacilities(acc.Id, 'Origin Address');
        Test.stopTest();

        System.assertEquals(2, results.size(), 'Expect only distinct parent territories to be returned');

        // With deterministic sorting, first address should be Territory A.
        Map<String, Object> first = results[0];
        System.assertEquals('123 A St, City A, CA, 90001, USA', (String) first.get('address'));
        System.assert(first.containsKey('minutes'));
        System.assert(first.containsKey('distanceMiles'));
        System.assertNotEquals(null, first.get('latitude'));
        System.assertNotEquals(null, first.get('longitude'));

        for (Map<String, Object> result : results) {
            String address = (String) result.get('address');
            System.assertNotEquals(true, address.contains('789 Child St'), 'Child territory should not be included');
            System.assertNotEquals(true, address.contains('101 Child Two St'), 'Child territory should not be included');
        }

        Set<String> uniqueAddresses = new Set<String>();
        for (Map<String, Object> result : results) {
            uniqueAddresses.add((String) result.get('address'));
        }
        System.assertEquals(results.size(), uniqueAddresses.size(), 'Result addresses should be unique');
    }

    @isTest
    static void testGetAccountBillingAddress() {
        Account acc = new Account(
            Name = 'Billing Account',
            BillingStreet = '1 Main St',
            BillingCity = 'City',
            BillingState = 'ST',
            BillingPostalCode = '12345',
            BillingCountry = 'USA'
        );
        insert acc;

        String address = GnalFacilitySearchController.getAccountBillingAddress(acc.Id);
        System.assertEquals('1 Main St, City, ST, 12345, USA', address);
    }

    @isTest
    static void testGetLatestCaseOriginAddressReturnsNullWhenMissing() {
        Test.startTest();
        String latestOrigin = GnalFacilitySearchController.getLatestCaseOriginAddress();
        Test.stopTest();
        System.assertEquals(null, latestOrigin);
    }
}
