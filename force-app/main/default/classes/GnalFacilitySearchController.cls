public with sharing class GnalFacilitySearchController {

    @AuraEnabled(cacheable=false)
    public static List<Map<String, Object>> findNearestFacilities(Id accountId, String originAddress) {
        List<String> destinationAddresses = new List<String>();
        for (Facilities__c facility : [
            SELECT Id, Address__c
            FROM Facilities__c
            WHERE Address__c != null
        ]) {
            destinationAddresses.add(facility.Address__c);
        }

        if (destinationAddresses.isEmpty()) {
            throw new AuraHandledException('No facilities found with addresses.');
        }

        List<GnalTravelTimeServiceWithGeocoding.TravelTimeResult> travelTimes =
            GnalTravelTimeServiceWithGeocoding.getTravelTimesFromAddresses(originAddress, destinationAddresses);

        List<Map<String, Object>> formattedResults = new List<Map<String, Object>>();
        for (GnalTravelTimeServiceWithGeocoding.TravelTimeResult travelTime : travelTimes) {
            formattedResults.add(new Map<String, Object>{
                'address'        => travelTime.address,
                'minutes'        => travelTime.minutes,
                'distanceMeters' => travelTime.distanceMeters,
                'distanceMiles'  => travelTime.distanceMiles,
                'latitude'       => travelTime.latitude,
                'longitude'      => travelTime.longitude
            });
        }

        return formattedResults;
    }

    @AuraEnabled(cacheable=true)
    public static String getAccountBillingAddress(Id accountId) {
        Account acc = [
            SELECT BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry
            FROM Account WHERE Id = :accountId
            LIMIT 1
        ];
        List<String> parts = new List<String>();
        if (acc.BillingStreet != null) parts.add(acc.BillingStreet);
        if (acc.BillingCity != null) parts.add(acc.BillingCity);
        if (acc.BillingState != null) parts.add(acc.BillingState);
        if (acc.BillingPostalCode != null) parts.add(acc.BillingPostalCode);
        if (acc.BillingCountry != null) parts.add(acc.BillingCountry);
        return String.join(parts, ', ');
    }
}
