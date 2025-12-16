public with sharing class GnalTravelTimeServiceWithGeocoding {

    public class TravelTimeResult implements Comparable {
        @AuraEnabled public String address;
        @AuraEnabled public Double minutes;
        @AuraEnabled public Double distanceMeters;
        @AuraEnabled public Double distanceMiles;
        @AuraEnabled public Double latitude;
        @AuraEnabled public Double longitude;
        @AuraEnabled public Double originLatitude;
        @AuraEnabled public Double originLongitude;

        public TravelTimeResult(
            String address,
            Double minutes,
            Double distanceMeters,
            Double distanceMiles,
            Double latitude,
            Double longitude,
            Double originLatitude,
            Double originLongitude
        ) {
            this.address = address;
            this.minutes = minutes;
            this.distanceMeters = distanceMeters;
            this.distanceMiles = distanceMiles;
            this.latitude = latitude;
            this.longitude = longitude;
            this.originLatitude = originLatitude;
            this.originLongitude = originLongitude;
        }

        public Integer compareTo(Object compareTo) {
            TravelTimeResult other = (TravelTimeResult) compareTo;
            if (minutes == null && other.minutes == null) return 0;
            if (minutes == null) return 1;
            if (other.minutes == null) return -1;
            if (minutes == other.minutes) return 0;
            return minutes < other.minutes ? -1 : 1;
        }
    }

    private static final String GEOCODE_URL = Label.Google_Geocode_URL;
    private static final String ROUTE_MATRIX_URL = Label.Google_Route_Matrix_URL;
    private static final String API_KEY = Label.Google_Maps_API_Key;
    private static final String ROUTE_FIELD_MASK = 'originIndex,destinationIndex,status,distanceMeters,duration';
    private static final Double METERS_PER_MILE = 1609.344;

    @AuraEnabled
    public static List<TravelTimeResult> getTravelTimesFromAddresses(
        String originAddress,
        List<String> destinationAddresses
    ) {
        validateGoogleConfig();
        if (String.isBlank(originAddress)) {
            throw new AuraHandledException('Origin address is required.');
        }
        if (destinationAddresses == null || destinationAddresses.isEmpty()) {
            throw new AuraHandledException('At least one destination address is required.');
        }

        Map<String, Double> originLatLng = getLatLngFromAddress(originAddress);
        if (originLatLng == null) {
            throw new AuraHandledException('Failed to geocode origin address.');
        }

        List<Map<String, Double>> destinationLatLngList = new List<Map<String, Double>>();
        List<String> routedDestinationAddresses = new List<String>();
        for (String destination : destinationAddresses) {
            Map<String, Double> destLatLng = getLatLngFromAddress(destination);
            if (destLatLng != null) {
                destinationLatLngList.add(destLatLng);
                routedDestinationAddresses.add(destination);
            }
        }

        if (destinationLatLngList.isEmpty()) {
            throw new AuraHandledException('Failed to geocode destinations.');
        }

        List<Object> origins = new List<Object>{
            new Map<String, Object>{
                'waypoint' => new Map<String, Object>{
                    'location' => new Map<String, Object>{
                        'latLng' => new Map<String, Object>{
                            'latitude' => originLatLng.get('lat'),
                            'longitude' => originLatLng.get('lng')
                        }
                    }
                }
            }
        };

        List<Object> destinations = new List<Object>();
        for (Map<String, Double> latLng : destinationLatLngList) {
            destinations.add(new Map<String, Object>{
                'waypoint' => new Map<String, Object>{
                    'location' => new Map<String, Object>{
                        'latLng' => new Map<String, Object>{
                            'latitude' => latLng.get('lat'),
                            'longitude' => latLng.get('lng')
                        }
                    }
                }
            });
        }

        Map<String, Object> reqBody = new Map<String, Object>{
            'origins' => origins,
            'destinations' => destinations,
            'travelMode' => 'DRIVE',
            'routingPreference' => 'TRAFFIC_AWARE'
        };

        HttpRequest routeRequest = buildPostRequest(ROUTE_MATRIX_URL, reqBody, ROUTE_FIELD_MASK);
        Http http = new Http();
        HTTPResponse routeResponse;
        try {
            routeResponse = http.send(routeRequest);
        } catch (Exception ex) {
            throw new AuraHandledException('Google Route Matrix callout failed: ' + ex.getMessage());
        }

        if (routeResponse.getStatusCode() != 200) {
            throw new AuraHandledException('Route API error: ' + routeResponse.getStatusCode() + ' - ' + routeResponse.getBody());
        }

        List<Object> parsedPayload = (List<Object>) JSON.deserializeUntyped(routeResponse.getBody());
        List<TravelTimeResult> results = new List<TravelTimeResult>();

        for (Object payloadObj : parsedPayload) {
            Map<String, Object> row = (Map<String, Object>) payloadObj;
            Integer destinationIndex = ((Double) row.get('destinationIndex')).intValue();
            String addressKey = routedDestinationAddresses[destinationIndex];
            Map<String, Double> destLatLng = destinationLatLngList[destinationIndex];

            String durationLiteral = (String) row.get('duration');
            Double seconds = 0;
            if (!String.isBlank(durationLiteral) && durationLiteral.endsWith('s')) {
                seconds = Double.valueOf(durationLiteral.substring(0, durationLiteral.length() - 1));
            }

            Double minutes = seconds / 60;
            Double distanceMeters = row.containsKey('distanceMeters') ? (Double) row.get('distanceMeters') : null;
            Double distanceMiles = metersToMiles(distanceMeters);

            results.add(new TravelTimeResult(
                addressKey,
                minutes,
                distanceMeters,
                distanceMiles,
                destLatLng != null ? destLatLng.get('lat') : null,
                destLatLng != null ? destLatLng.get('lng') : null,
                originLatLng.get('lat'),
                originLatLng.get('lng')
            ));
        }

        results.sort();
        return results;
    }

    public static Map<String, Double> getLatLngFromAddress(String address) {
        if (String.isBlank(address)) {
            return null;
        }

        validateGoogleConfig();
        String encodedAddr = EncodingUtil.urlEncode(address, 'UTF-8');
        String url = GEOCODE_URL + '?address=' + encodedAddr + '&key=' + API_KEY;
        HttpRequest request = buildGetRequest(url);
        HttpResponse response;
        try {
            response = new Http().send(request);
        } catch (Exception ex) {
            throw new AuraHandledException('Google Geocode callout failed: ' + ex.getMessage());
        }

        if (response.getStatusCode() != 200) {
            throw new AuraHandledException('Geocode API error: ' + response.getStatusCode() + ' - ' + response.getBody());
        }

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
        List<Object> results = (List<Object>) body.get('results');
        if (results == null || results.isEmpty()) {
            return null;
        }

        Map<String, Object> firstResult = (Map<String, Object>) results[0];
        Map<String, Object> geometry = (Map<String, Object>) firstResult.get('geometry');
        Map<String, Object> location = (Map<String, Object>) geometry.get('location');
        return new Map<String, Double>{
            'lat' => (Double) location.get('lat'),
            'lng' => (Double) location.get('lng')
        };
    }

    private static void validateGoogleConfig() {
        List<String> missing = new List<String>();
        if (String.isBlank(GEOCODE_URL)) missing.add('Google_Geocode_URL');
        if (String.isBlank(ROUTE_MATRIX_URL)) missing.add('Google_Route_Matrix_URL');
        if (String.isBlank(API_KEY)) missing.add('Google_Maps_API_Key');
        if (!missing.isEmpty()) {
            throw new AuraHandledException('Google Maps configuration missing: ' + String.join(missing, ', '));
        }
    }

    private static HttpRequest buildPostRequest(String endpoint, Object body, String fieldMask) {
        HttpRequest request = initRequest(endpoint);
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json;charset=UTF-8');
        if (!String.isBlank(fieldMask)) {
            request.setHeader('X-Goog-FieldMask', fieldMask);
        }
        if (body != null) {
            request.setBody(JSON.serialize(body));
        }
        return request;
    }

    private static HttpRequest buildGetRequest(String endpoint) {
        HttpRequest request = initRequest(endpoint);
        request.setMethod('GET');
        return request;
    }

    private static HttpRequest initRequest(String endpoint) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint(endpoint);
        request.setTimeout(120000);
        if (!String.isBlank(API_KEY)) {
            request.setHeader('X-Goog-Api-Key', API_KEY);
        }
        return request;
    }

    private static Double metersToMiles(Double meters) {
        return meters == null ? null : meters / METERS_PER_MILE;
    }
}
