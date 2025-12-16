public with sharing class GnalFacilitySearchController {

    private static final Double DEFAULT_RADIUS_MILES = 100;
    private static final Map<String, Schema.SObjectField> CACHE_FIELD_MAP =
        Schema.SObjectType.GeocodeCache__c.fields.getMap();

    @AuraEnabled(cacheable=false)
    public static List<Map<String, Object>> findNearestFacilitiesWithRadius(
        Id accountId,
        String originAddress,
        Double radiusMiles
    ) {
        return findNearestFacilitiesInternal(accountId, originAddress, radiusMiles);
    }

    @AuraEnabled(cacheable=false)
    public static List<Map<String, Object>> findNearestFacilities(Id accountId, String originAddress) {
        return findNearestFacilitiesInternal(accountId, originAddress, null);
    }

    private static List<Map<String, Object>> findNearestFacilitiesInternal(
        Id accountId,
        String originAddress,
        Double radiusMiles
    ) {
        if (String.isBlank(originAddress)) {
            throw new AuraHandledException('Origin address is required.');
        }

        Double effectiveRadius = radiusMiles;
        if (effectiveRadius == null || effectiveRadius <= 0) {
            effectiveRadius = DEFAULT_RADIUS_MILES;
        }

        List<ServiceTerritory> territories = getDistinctTerritories();
        if (territories.isEmpty()) {
            throw new AuraHandledException('No facilities found with addresses.');
        }

        Set<String> destinationAddressSet = new Set<String>();
        for (ServiceTerritory territory : territories) {
            String formattedAddress = formatServiceTerritoryAddress(territory);
            if (!String.isBlank(formattedAddress)) {
                destinationAddressSet.add(formattedAddress);
            }
        }

        if (destinationAddressSet.isEmpty()) {
            throw new AuraHandledException('No facilities found with addresses.');
        }

        // Make ordering deterministic to avoid flaky indexing/mapping.
        List<String> destinationAddresses = new List<String>(destinationAddressSet);
        destinationAddresses.sort();

        CacheContext cacheContext = ensureCacheCoverage(originAddress, destinationAddresses);
        if (cacheContext.originLatitude == null || cacheContext.originLongitude == null) {
            throw new AuraHandledException('Unable to determine origin coordinates.');
        }

        List<GeocodeCache__c> filteredCaches = queryCachesWithinRadius(
            originAddress,
            destinationAddresses,
            cacheContext.originLatitude,
            cacheContext.originLongitude,
            effectiveRadius
        );

        if (filteredCaches.isEmpty()) {
            throw new AuraHandledException('No facilities found within the selected distance.');
        }

        return formatCacheResults(filteredCaches);
    }

    @AuraEnabled(cacheable=true)
    public static String getLatestCaseOriginAddress() {
        String userName = UserInfo.getName();

        List<Case> casesWithOrigin = [
            SELECT GNAL_Origin_Location__c
            FROM Case
            WHERE Account.Name = :userName
            AND Origin = 'Phone'
            AND Status = 'New'
            AND GNAL_Origin_Location__c != null
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        return casesWithOrigin.isEmpty() ? null : casesWithOrigin[0].GNAL_Origin_Location__c;
    }

    private static List<ServiceTerritory> getDistinctTerritories() {
        List<ServiceTerritory> queriedTerritories = [
            SELECT Id, Name, IsActive, Address, Street, City, State, PostalCode, Country, ParentTerritoryId,
                   ParentTerritory.Id, ParentTerritory.Name, ParentTerritory.Address,
                   ParentTerritory.Street, ParentTerritory.City, ParentTerritory.State,
                   ParentTerritory.PostalCode, ParentTerritory.Country
            FROM ServiceTerritory
            WHERE IsActive = true
            ORDER BY Name
        ];

        List<ServiceTerritory> orderedTerritories = new List<ServiceTerritory>();
        Set<Id> seenTerritoryIds = new Set<Id>();

        for (ServiceTerritory territory : queriedTerritories) {
            if (territory.ParentTerritoryId == null) {
                addTerritoryIfNew(territory, orderedTerritories, seenTerritoryIds);
            }
        }

        for (ServiceTerritory territory : queriedTerritories) {
            if (territory.ParentTerritoryId != null && territory.ParentTerritory != null) {
                addTerritoryIfNew(territory.ParentTerritory, orderedTerritories, seenTerritoryIds);
            }
        }

        return orderedTerritories;
    }

    private static void addTerritoryIfNew(
        ServiceTerritory territory,
        List<ServiceTerritory> orderedTerritories,
        Set<Id> seenTerritoryIds
    ) {
        if (territory == null || territory.Id == null || seenTerritoryIds.contains(territory.Id)) {
            return;
        }
        seenTerritoryIds.add(territory.Id);
        orderedTerritories.add(territory);
    }

    private static CacheContext ensureCacheCoverage(String originAddress, List<String> destinationAddresses) {
        CacheContext context = new CacheContext();
        if (destinationAddresses == null || destinationAddresses.isEmpty()) {
            return context;
        }

        Map<String, GeocodeCache__c> existingCacheByAddress = new Map<String, GeocodeCache__c>();
        List<GeocodeCache__c> existingCacheRecords = [
            SELECT Id,
                   Origin_Address__c,
                   Destination_Address__c
            FROM GeocodeCache__c
            WHERE Origin_Address__c = :originAddress
            AND Destination_Address__c IN :destinationAddresses
        ];

        for (GeocodeCache__c cacheRecord : existingCacheRecords) {
            existingCacheByAddress.put(cacheRecord.Destination_Address__c, cacheRecord);
        }

        List<String> missingAddresses = new List<String>();
        for (String destinationAddress : destinationAddresses) {
            if (!existingCacheByAddress.containsKey(destinationAddress)) {
                missingAddresses.add(destinationAddress);
            }
        }

        if (!missingAddresses.isEmpty()) {
            List<GnalTravelTimeServiceWithGeocoding.TravelTimeResult> freshResults =
                GnalTravelTimeServiceWithGeocoding.getTravelTimesFromAddresses(originAddress, missingAddresses);

            List<GeocodeCache__c> cacheRecordsToInsert = buildCacheRecords(originAddress, freshResults);
            if (!cacheRecordsToInsert.isEmpty()) {
                insert cacheRecordsToInsert;
            }

            if (context.originLatitude == null && !freshResults.isEmpty()) {
                context.originLatitude = freshResults[0].originLatitude;
                context.originLongitude = freshResults[0].originLongitude;
            }
        }

        if (context.originLatitude == null || context.originLongitude == null) {
            Map<String, Double> originLatLng = GnalTravelTimeServiceWithGeocoding.getLatLngFromAddress(originAddress);
            if (originLatLng != null) {
                context.originLatitude = originLatLng.get('lat');
                context.originLongitude = originLatLng.get('lng');
            }
        }

        return context;
    }

    private static List<GeocodeCache__c> queryCachesWithinRadius(
        String originAddress,
        List<String> destinationAddresses,
        Double originLatitude,
        Double originLongitude,
        Double radiusMiles
    ) {
        if (destinationAddresses == null || destinationAddresses.isEmpty()) {
            return new List<GeocodeCache__c>();
        }
        if (originLatitude == null || originLongitude == null) {
            return new List<GeocodeCache__c>();
        }

        Location originLocation = Location.newInstance(originLatitude, originLongitude);

        Double radiusFilter = radiusMiles + 0.000001;

        return [
            SELECT Id,
                   Origin_Address__c,
                   Destination_Address__c,
                   Distance_Miles__c,
                   Distance_Meters__c,
                   Travel_Time_Minutes__c,
                   Destination_Location__Latitude__s,
                   Destination_Location__Longitude__s,
                   Destination_Location__c
            FROM GeocodeCache__c
            WHERE Origin_Address__c = :originAddress
            AND Destination_Address__c IN :destinationAddresses
            AND DISTANCE(Destination_Location__c, :originLocation, 'mi') < :radiusFilter
            ORDER BY Distance_Miles__c ASC NULLS LAST
        ];
    }

    private static List<GeocodeCache__c> buildCacheRecords(
        String originAddress,
        List<GnalTravelTimeServiceWithGeocoding.TravelTimeResult> travelTimes
    ) {
        List<GeocodeCache__c> cacheRecords = new List<GeocodeCache__c>();
        if (travelTimes == null) {
            return cacheRecords;
        }

        for (GnalTravelTimeServiceWithGeocoding.TravelTimeResult travelTime : travelTimes) {
            if (travelTime == null || String.isBlank(travelTime.address)) {
                continue;
            }

            GeocodeCache__c cacheRecord = new GeocodeCache__c();
            cacheRecord.Origin_Address__c = originAddress;
            cacheRecord.Destination_Address__c = travelTime.address;
            cacheRecord.Distance_Miles__c = travelTime.distanceMiles;
            cacheRecord.Distance_Meters__c = travelTime.distanceMeters;
            cacheRecord.Travel_Time_Minutes__c = travelTime.minutes;

            if (travelTime.latitude != null && travelTime.longitude != null) {
                setLocationField(cacheRecord, 'Destination_Location__c', travelTime.latitude, travelTime.longitude);
            }

            cacheRecords.add(cacheRecord);
        }

        return cacheRecords;
    }

    private static List<Map<String, Object>> formatCacheResults(List<GeocodeCache__c> cacheRecords) {
        List<Map<String, Object>> formattedResults = new List<Map<String, Object>>();
        for (GeocodeCache__c cacheEntry : cacheRecords) {
            Double latitude = cacheEntry.Destination_Location__Latitude__s;
            Double longitude = cacheEntry.Destination_Location__Longitude__s;

            formattedResults.add(new Map<String, Object>{
                'address'        => cacheEntry.Destination_Address__c,
                'minutes'        => cacheEntry.Travel_Time_Minutes__c,
                'distanceMeters' => cacheEntry.Distance_Meters__c,
                'distanceMiles'  => cacheEntry.Distance_Miles__c,
                'latitude'       => latitude,
                'longitude'      => longitude
            });
        }
        return formattedResults;
    }

    private static void setLocationField(
        SObject record,
        String fieldApiName,
        Double latitude,
        Double longitude
    ) {
        if (record == null || String.isBlank(fieldApiName) || latitude == null || longitude == null) {
            return;
        }

        // For custom geolocation fields, the compound field itself is not always marked createable,
        // but the backing latitude/longitude subfields usually are. Populate whichever is writable
        // so that DISTANCE() filters work reliably.
        Schema.SObjectField field = CACHE_FIELD_MAP != null ? CACHE_FIELD_MAP.get(fieldApiName) : null;
        Boolean wroteAny = false;

        if (field != null && field.getDescribe().isCreateable()) {
            record.put(fieldApiName, Location.newInstance(latitude, longitude));
            wroteAny = true;
        }

        if (!wroteAny && fieldApiName.endsWith('__c')) {
            String latFieldApiName = fieldApiName.substring(0, fieldApiName.length() - 3) + '__Latitude__s';
            String lonFieldApiName = fieldApiName.substring(0, fieldApiName.length() - 3) + '__Longitude__s';

            Schema.SObjectField latField = CACHE_FIELD_MAP != null ? CACHE_FIELD_MAP.get(latFieldApiName) : null;
            Schema.SObjectField lonField = CACHE_FIELD_MAP != null ? CACHE_FIELD_MAP.get(lonFieldApiName) : null;

            if (latField != null && latField.getDescribe().isCreateable()) {
                record.put(latFieldApiName, latitude);
                wroteAny = true;
            }
            if (lonField != null && lonField.getDescribe().isCreateable()) {
                record.put(lonFieldApiName, longitude);
                wroteAny = true;
            }
        }
    }

    private class CacheContext {
        Double originLatitude;
        Double originLongitude;
    }

    private static String formatServiceTerritoryAddress(ServiceTerritory territory) {
        if (territory == null) {
            return null;
        }
        List<String> parts = new List<String>();
        if (!String.isBlank(territory.Street))     parts.add(territory.Street);
        if (!String.isBlank(territory.City))       parts.add(territory.City);
        if (!String.isBlank(territory.State))      parts.add(territory.State);
        if (!String.isBlank(territory.PostalCode)) parts.add(territory.PostalCode);
        if (!String.isBlank(territory.Country))    parts.add(territory.Country);
        return parts.isEmpty() ? null : String.join(parts, ', ');
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
