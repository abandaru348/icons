@IsTest
private class GnalTravelTimeServiceWithGeocodingTest {

    private class GoogleMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            
            // Be endpoint-agnostic: orgs may configure real Google endpoints via labels.
            // Use HTTP method to distinguish Geocode (GET) vs Route Matrix (POST).
            if (req.getMethod() == 'GET') {
                // Minimal Google Geocode response shape
                res.setBody('{' +
                    '"results":[{' +
                        '"geometry":{"location":{"lat":30.0001,"lng":-97.0001}}' +
                    '}],' +
                    '"status":"OK"' +
                '}');
                return res;
            }

            if (req.getMethod() == 'POST') {
                // Minimal Route Matrix response shape: list of entries
                // Destination 0 -> 600s, Destination 1 -> 1200s
                res.setBody('[' +
                    '{"originIndex":0.0,"destinationIndex":0.0,"status":"OK","distanceMeters":1609.344,"duration":"600s"},' +
                    '{"originIndex":0.0,"destinationIndex":1.0,"status":"OK","distanceMeters":3218.688,"duration":"1200s"}' +
                ']');
                return res;
            }

            // Unknown endpoint
            res.setStatusCode(404);
            res.setBody('Not Found');
            return res;
        }
    }

    private class GoogleMockGeocode500 implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            if (req.getMethod() == 'GET') {
                res.setStatusCode(500);
                res.setBody('geocode failed');
                return res;
            }
            // Route matrix OK so we isolate geocode failure
            res.setStatusCode(200);
            res.setBody('[]');
            return res;
        }
    }

    private class GoogleMockRoute500 implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            if (req.getMethod() == 'GET') {
                res.setStatusCode(200);
                res.setBody('{' +
                    '"results":[{' +
                        '"geometry":{"location":{"lat":30.0001,"lng":-97.0001}}' +
                    '}],' +
                    '"status":"OK"' +
                '}');
                return res;
            }
            // Route matrix failure
            res.setStatusCode(500);
            res.setBody('route failed');
            return res;
        }
    }

    @IsTest
    static void getLatLngFromAddress_returnsLatLng() {
        Test.setMock(HttpCalloutMock.class, new GoogleMock());

        Test.startTest();
        Map<String, Double> latLng = GnalTravelTimeServiceWithGeocoding.getLatLngFromAddress('Austin, TX');
        Test.stopTest();

        System.assertNotEquals(null, latLng);
        System.assertEquals(true, latLng.containsKey('lat'));
        System.assertEquals(true, latLng.containsKey('lng'));
        System.assertEquals(30.0001, latLng.get('lat'));
        System.assertEquals(-97.0001, latLng.get('lng'));
    }

    @IsTest
    static void getTravelTimesFromAddresses_dedupesAndReturnsSortedResults() {
        Test.setMock(HttpCalloutMock.class, new GoogleMock());

        List<String> destinations = new List<String>{
            'Dest A',
            'Dest B',
            'Dest A' // duplicate to cover dedupe
        };

        Test.startTest();
        List<GnalTravelTimeServiceWithGeocoding.TravelTimeResult> results =
            GnalTravelTimeServiceWithGeocoding.getTravelTimesFromAddresses('Origin', destinations);
        Test.stopTest();

        System.assertEquals(2, results.size(), 'Should return unique destinations only');
        System.assertEquals('Dest A', results[0].address, 'Shortest duration should sort first');
        System.assertEquals(10, Math.round(results[0].minutes), '600s => 10 minutes');
        System.assertEquals(20, Math.round(results[1].minutes), '1200s => 20 minutes');
        System.assertNotEquals(null, results[0].originLatitude);
        System.assertNotEquals(null, results[0].originLongitude);
        System.assertNotEquals(null, results[0].latitude);
        System.assertNotEquals(null, results[0].longitude);
    }

    @IsTest
    static void getLatLngFromAddress_non200_throws() {
        Test.setMock(HttpCalloutMock.class, new GoogleMockGeocode500());
        Boolean threw = false;
        try {
            Test.startTest();
            GnalTravelTimeServiceWithGeocoding.getLatLngFromAddress('Austin, TX');
        } catch (Exception ex) {
            threw = true;
            System.assert(String.valueOf(ex.getMessage()).contains('Geocode API error'));
        } finally {
            Test.stopTest();
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void getTravelTimesFromAddresses_routeNon200_throws() {
        Test.setMock(HttpCalloutMock.class, new GoogleMockRoute500());
        Boolean threw = false;
        try {
            Test.startTest();
            GnalTravelTimeServiceWithGeocoding.getTravelTimesFromAddresses('Origin', new List<String>{ 'Dest A' });
        } catch (Exception ex) {
            threw = true;
            System.assert(String.valueOf(ex.getMessage()).contains('Route API error'));
        } finally {
            Test.stopTest();
        }
        System.assertEquals(true, threw);
    }
}

