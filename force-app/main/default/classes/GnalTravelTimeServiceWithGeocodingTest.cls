@IsTest
private class GnalTravelTimeServiceWithGeocodingTest {

    private class MockCallout implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);

            if (req.getEndpoint().contains('geocode')) {
                // Minimal geocode response with lat/lng
                res.setBody('{"results":[{"geometry":{"location":{"lat":10.0,"lng":20.0}}}],"status":"OK"}');
            } else if (req.getEndpoint().contains('distanceMatrix')) {
                // Two destinations: first is faster
                res.setBody('[{"destinationIndex":0,"duration":"100s","distanceMeters":5000},'
                            + '{"destinationIndex":1,"duration":"200s","distanceMeters":7000}]');
            }
            return res;
        }
    }

    @IsTest
    static void testGetTravelTimes() {
        Test.setMock(HttpCalloutMock.class, new MockCallout());

        String origin = '123 Main St';
        List<String> destinations = new List<String>{'Dest A', 'Dest B'};

        Test.startTest();
        List<GnalTravelTimeServiceWithGeocoding.TravelTimeResult> results =
            GnalTravelTimeServiceWithGeocoding.getTravelTimesFromAddresses(origin, destinations);
        Test.stopTest();

        System.assertEquals(2, results.size());
        System.assertEquals('Dest A', results[0].address);
        System.assert(results[0].minutes < results[1].minutes);
        System.assertEquals(10.0, results[0].latitude);
        System.assertEquals(20.0, results[0].longitude);
    }
}

