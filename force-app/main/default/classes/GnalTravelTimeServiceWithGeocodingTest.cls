@IsTest
private class GnalTravelTimeServiceWithGeocodingTest {

    @IsTest
    static void getTravelTimesFromAddresses_sortsAndPopulatesLatLng() {
        Test.setMock(HttpCalloutMock.class, new GnalRouteMatrixCalloutMock());

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
        Test.setMock(HttpCalloutMock.class, new GnalRouteMatrixCalloutMock());

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

