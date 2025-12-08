@isTest
private class GnalFacilitySearchControllerTest {

    private class MockCallout implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);

            if (req.getEndpoint().contains('geocode')) {
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

        insert new Facilities__c(Name = 'Facility A', Address__c = '123 A St');
        insert new Facilities__c(Name = 'Facility B', Address__c = '456 B St');

        Test.setMock(HttpCalloutMock.class, new MockCallout());

        Test.startTest();
        List<Map<String, Object>> results = GnalFacilitySearchController.findNearestFacilities(acc.Id, 'Origin Address');
        Test.stopTest();

        System.assertEquals(2, results.size(), 'Expect two facilities');
        Map<String, Object> first = results[0];
        System.assertEquals('123 A St', (String) first.get('address'));
        System.assert(first.containsKey('minutes'));
        System.assert(first.containsKey('distanceMiles'));
        System.assertNotEquals(null, first.get('latitude'));
        System.assertNotEquals(null, first.get('longitude'));
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
}
