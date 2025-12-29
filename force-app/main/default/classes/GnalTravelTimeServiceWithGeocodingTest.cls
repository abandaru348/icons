@IsTest
private class GnalTravelTimeServiceWithGeocodingTest {

    /**
     * Mocks the Route Matrix callout.
     *
     * Note: In tests, GnalTravelTimeServiceWithGeocoding.getLatLngFromAddress() returns
     * deterministic coordinates (no geocode callout), so the only callout here is the POST
     * to the route-matrix endpoint.
     */
    private class MockRouteMatrixCallout implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();

            if (req != null && req.getMethod() == 'POST') {
                res.setStatusCode(200);
                // Two destinations: first is faster/shorter.
                res.setBody(
                    '[' +
                        '{"originIndex":0,"destinationIndex":0,"status":"OK","duration":"100s","distanceMeters":5000},' +
                        '{"originIndex":0,"destinationIndex":1,"status":"OK","duration":"200s","distanceMeters":7000}' +
                    ']'
                );
                return res;
            }

            res.setStatusCode(400);
            res.setBody('Unsupported request');
            return res;
        }
    }

    @IsTest
    static void getTravelTimesFromAddresses_sortsAndPopulatesLatLng() {
        Test.setMock(HttpCalloutMock.class, new MockRouteMatrixCallout());

        String origin = '123 Main St';
        List<String> destinations = new List<String>{ 'Dest A', 'Dest B' };

        Test.startTest();
        List<GnalTravelTimeServiceWithGeocoding.TravelTimeResult> results =
            GnalTravelTimeServiceWithGeocoding.getTravelTimesFromAddresses(origin, destinations);
        Test.stopTest();

        System.assertEquals(2, results.size());
        System.assertEquals('Dest A', results[0].address);
        System.assertEquals('Dest B', results[1].address);
        System.assert(results[0].minutes < results[1].minutes, 'Expected sorted by minutes ascending');

        // In tests, lat/lng come from deterministic in-test geocoding (not from callout).
        System.assertEquals(30.2672, results[0].latitude);
        System.assertEquals(-97.7431, results[0].longitude);
        System.assertEquals(30.2672, results[0].originLatitude);
        System.assertEquals(-97.7431, results[0].originLongitude);
    }

    @IsTest
    static void getTravelTimesFromAddresses_blankOrigin_throwsAuraHandledException() {
        Test.setMock(HttpCalloutMock.class, new MockRouteMatrixCallout());

        Boolean threw = false;
        try {
            Test.startTest();
            GnalTravelTimeServiceWithGeocoding.getTravelTimesFromAddresses('', new List<String>{ 'Dest A' });
        } catch (AuraHandledException ex) {
            threw = true;
        } finally {
            Test.stopTest();
        }
        System.assertEquals(true, threw);
    }
}

