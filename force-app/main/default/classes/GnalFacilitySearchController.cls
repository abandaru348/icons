public with sharing class GnalFacilitySearchController {

    private static final Double DEFAULT_RADIUS_MILES = 100;
    // DISTANCE() filtering can behave slightly differently at the boundary due to floating-point rounding.
    // Add a tiny epsilon to the radius so results exactly on the boundary aren't intermittently excluded.
    private static final Double DISTANCE_EPSILON_MILES = 0.000001;
    // Prevent callout-limit failures when there are many facilities.
    // We progressively warm the cache across searches instead of attempting to geocode everything at once.
    private static final Integer MAX_DESTINATIONS_TO_CACHE_PER_REQUEST = 25;
    private static final Map<String, Schema.SObjectField> CACHE_FIELD_MAP =
        Schema.SObjectType.GeocodeCache__c.fields.getMap();
    private static final String OPTIONAL_ORIGIN_FIELDS_SELECT = initOptionalOriginFieldsSelect();

    // Cache-first facility search. Will only call Google when a cache miss occurs.
    @AuraEnabled(cacheable=false)
    public static List<Map<String, Object>> findNearestFacilitiesWithRadius(
        Id accountId,
        String originAddress,
        Double radiusMiles
    ) {
        try {
            return findNearestFacilitiesInternal(accountId, originAddress, radiusMiles);
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException(formatExceptionForClient('Facility search failed', ex));
        }
    }

    // Cache-only radius search: does NOT call Google. Intended for radius changes in the LWC.
    @AuraEnabled(cacheable=false)
    public static List<Map<String, Object>> findFacilitiesFromCacheWithRadius(
        String originAddress,
        Double radiusMiles
    ) {
        try {
            if (String.isBlank(originAddress)) {
                throw new AuraHandledException('Origin address is required.');
            }

            Double effectiveRadius = radiusMiles;
            if (effectiveRadius == null || effectiveRadius <= 0) {
                effectiveRadius = DEFAULT_RADIUS_MILES;
            }

            LatLng origin = getOriginLatLngFromAnyCacheRow(originAddress);
            if (origin == null || origin.lat == null || origin.lng == null) {
                // No cached origin coordinates yet; user should run the main search to warm cache.
                return new List<Map<String, Object>>();
            }

            List<GeocodeCache__c> filteredCaches = queryCachesWithinRadiusAllCached(
                originAddress,
                origin.lat,
                origin.lng,
                effectiveRadius
            );

            return formatCacheResults(filteredCaches);
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException(formatExceptionForClient('Cache radius search failed', ex));
        }
    }

    @AuraEnabled(cacheable=false)
    public static List<Map<String, Object>> findNearestFacilities(Id accountId, String originAddress) {
        try {
            return findNearestFacilitiesInternal(accountId, originAddress, null);
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException(formatExceptionForClient('Facility search failed', ex));
        }
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

        // Deterministic ordering reduces flaky result ordering.
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

        return formatCacheResults(filteredCaches);
    }

    /**
     * Requirement: prepopulate origin from latest Case of logged-in user where
     * - Case.AccountId = logged in user's AccountId
     * - Origin = 'Phone'
     * - Status = 'New'
     * - Order by CreatedDate desc, limit 1
     */
    @AuraEnabled(cacheable=true)
    public static String getLatestCaseOriginAddress() {
        // Some orgs do not expose relationship fields like User.AccountId or User.ContactId.
        // Use schema-aware dynamic SOQL to query only fields that exist, then derive an AccountId if possible.
        Id userId = UserInfo.getUserId();
        Map<String, Schema.SObjectField> userFields = Schema.SObjectType.User.fields.getMap();
        Boolean hasUserAccountId = userFields != null && userFields.containsKey('AccountId');
        Boolean hasUserContactId = userFields != null && userFields.containsKey('ContactId');

        List<String> selectFields = new List<String>{ 'Id', 'Name' };
        if (hasUserAccountId) selectFields.add('AccountId');
        if (hasUserContactId) selectFields.add('ContactId');

        String userSoql =
            'SELECT ' + String.join(selectFields, ', ') +
            ' FROM User WHERE Id = ' + quoteSoql(String.valueOf(userId)) +
            ' LIMIT 1';
        User u = (User) Database.query(userSoql);

        Id resolvedAccountId;
        // 1) If the org actually has User.AccountId, prefer it.
        if (hasUserAccountId) {
            resolvedAccountId = (Id) u.get('AccountId');
        }
        // 2) If the org has User.ContactId, derive Contact.AccountId.
        if (resolvedAccountId == null && hasUserContactId) {
            Id contactId = (Id) u.get('ContactId');
            if (contactId != null) {
                Contact c = [
                    SELECT AccountId
                    FROM Contact
                    WHERE Id = :contactId
                    LIMIT 1
                ];
                resolvedAccountId = c.AccountId;
            }
        }

        List<Case> casesWithOrigin;
        if (resolvedAccountId != null) {
            casesWithOrigin = [
                SELECT Id, GNAL_Origin_Location__c
                FROM Case
                WHERE AccountId = :resolvedAccountId
                AND Origin = 'Phone'
                AND Status = 'New'
                AND GNAL_Origin_Location__c != null
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
        } else {
            // Fallback for orgs where a User isn't tied to a Contact/Account (or those fields don't exist).
            casesWithOrigin = [
                SELECT Id, GNAL_Origin_Location__c
                FROM Case
                WHERE Account.Name = :u.Name
                AND Origin = 'Phone'
                AND Status = 'New'
                AND GNAL_Origin_Location__c != null
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
        }

        return casesWithOrigin.isEmpty() ? null : casesWithOrigin[0].GNAL_Origin_Location__c;
    }

    // Preferred overload for this LWC: the component lives on an Account record page,
    // so we can reliably query the latest Case for that Account.
    @AuraEnabled(cacheable=true)
    public static String getLatestCaseOriginAddressForAccount(Id accountId) {
        if (accountId == null) {
            return null;
        }

        // First try the strict requirement filters.
        List<Case> casesWithOrigin = [
            SELECT Id, GNAL_Origin_Location__c
            FROM Case
            WHERE AccountId = :accountId
            AND Origin = 'Phone'
            AND Status = 'New'
            AND GNAL_Origin_Location__c != null
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (!casesWithOrigin.isEmpty()) {
            return casesWithOrigin[0].GNAL_Origin_Location__c;
        }

        // Fallback: orgs often have different picklist values for Origin/Status.
        // Still prefer the latest Case on the Account that has GNAL origin populated.
        List<Case> anyWithOrigin = [
            SELECT Id, GNAL_Origin_Location__c
            FROM Case
            WHERE AccountId = :accountId
            AND GNAL_Origin_Location__c != null
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        return anyWithOrigin.isEmpty() ? null : anyWithOrigin[0].GNAL_Origin_Location__c;
    }

    private static List<ServiceTerritory> getDistinctTerritories() {
        List<ServiceTerritory> queriedTerritories = [
            SELECT Id, Name, IsActive, Street, City, State, PostalCode, Country, ParentTerritoryId,
                   ParentTerritory.Id, ParentTerritory.Name,
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

    /**
     * Ensures GeocodeCache__c contains rows for (originAddress, each destinationAddress).
     * Cache-first behavior:
     * - If a cache row exists: use it.
     * - If missing: call Google once per missing destination batch and insert.
     * Also ensures origin coordinates are derived from cache where possible to avoid
     * repeated origin geocode calls.
     */
    private static CacheContext ensureCacheCoverage(String originAddress, List<String> destinationAddresses) {
        CacheContext context = new CacheContext();
        if (destinationAddresses == null || destinationAddresses.isEmpty()) {
            return context;
        }

        Map<String, GeocodeCache__c> existingCacheByAddress = new Map<String, GeocodeCache__c>();
        List<GeocodeCache__c> existingCacheRecords = queryExistingCaches(originAddress, destinationAddresses);

        // If any cached row includes origin coordinates, reuse them.
        for (GeocodeCache__c cacheRecord : existingCacheRecords) {
            existingCacheByAddress.put(cacheRecord.Destination_Address__c, cacheRecord);
            if (context.originLatitude == null || context.originLongitude == null) {
                LatLng cachedOrigin = extractOriginLatLng(cacheRecord);
                if (cachedOrigin != null) {
                    context.originLatitude = cachedOrigin.lat;
                    context.originLongitude = cachedOrigin.lng;
                }
            }
        }

        List<String> missingAddresses = new List<String>();
        for (String destinationAddress : destinationAddresses) {
            if (!existingCacheByAddress.containsKey(destinationAddress)) {
                missingAddresses.add(destinationAddress);
            }
        }

        // Cache miss: call Google, then store results for future searches.
        if (!missingAddresses.isEmpty()) {
            // Avoid exceeding callout limits (TravelTimeService currently geocodes each destination).
            if (missingAddresses.size() > MAX_DESTINATIONS_TO_CACHE_PER_REQUEST) {
                List<String> limited = new List<String>();
                Integer limitSize = Math.min(MAX_DESTINATIONS_TO_CACHE_PER_REQUEST, missingAddresses.size());
                for (Integer i = 0; i < limitSize; i++) {
                    limited.add(missingAddresses[i]);
                }
                missingAddresses = limited;
            }
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

        // Backfill origin coords into existing cache rows if missing (one-time Google call).
        if ((context.originLatitude == null || context.originLongitude == null) && !existingCacheRecords.isEmpty()) {
            Map<String, Double> originLatLng = GnalTravelTimeServiceWithGeocoding.getLatLngFromAddress(originAddress);
            if (originLatLng != null) {
                context.originLatitude = originLatLng.get('lat');
                context.originLongitude = originLatLng.get('lng');

                List<GeocodeCache__c> toUpdate = new List<GeocodeCache__c>();
                for (GeocodeCache__c existingRow : existingCacheRecords) {
                    LatLng existingOrigin = extractOriginLatLng(existingRow);
                    if (existingOrigin == null) {
                        GeocodeCache__c updateRow = new GeocodeCache__c(Id = existingRow.Id);
                        writeOriginLatLng(updateRow, context.originLatitude, context.originLongitude, false);
                        toUpdate.add(updateRow);
                    }
                }
                if (!toUpdate.isEmpty()) {
                    update toUpdate;
                }
            }
        }

        // If there are no existing cache rows (should only happen when no destinations had addresses), last resort.
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
        Double radiusFilter = radiusMiles + DISTANCE_EPSILON_MILES;

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

    // Cache-only query (no destination IN list) for fast radius changes.
    private static List<GeocodeCache__c> queryCachesWithinRadiusAllCached(
        String originAddress,
        Double originLatitude,
        Double originLongitude,
        Double radiusMiles
    ) {
        if (String.isBlank(originAddress)) return new List<GeocodeCache__c>();
        if (originLatitude == null || originLongitude == null) return new List<GeocodeCache__c>();

        Location originLocation = Location.newInstance(originLatitude, originLongitude);
        Double radiusFilter = radiusMiles + DISTANCE_EPSILON_MILES;

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

        Long nowMillis = DateTime.now().getTime();
        Integer seq = 0;
        for (GnalTravelTimeServiceWithGeocoding.TravelTimeResult travelTime : travelTimes) {
            if (travelTime == null || String.isBlank(travelTime.address)) {
                continue;
            }

            GeocodeCache__c cacheRecord = new GeocodeCache__c();
            // Many orgs use Text Name fields, which are required. Keep deterministic + short.
            seq++;
            cacheRecord.Name = ('Geocode ' + String.valueOf(nowMillis) + '-' + String.valueOf(seq)).left(80);
            cacheRecord.Origin_Address__c = originAddress;
            cacheRecord.Destination_Address__c = travelTime.address;
            cacheRecord.Distance_Miles__c = travelTime.distanceMiles;
            cacheRecord.Distance_Meters__c = travelTime.distanceMeters;
            cacheRecord.Travel_Time_Minutes__c = travelTime.minutes;

            if (travelTime.originLatitude != null && travelTime.originLongitude != null) {
                writeOriginLatLng(cacheRecord, travelTime.originLatitude, travelTime.originLongitude, true);
            }

            if (travelTime.latitude != null && travelTime.longitude != null) {
                setLocationField(cacheRecord, 'Destination_Location__c', travelTime.latitude, travelTime.longitude, true);
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

    /**
     * Writes a geolocation field in a way that works even when the compound field isn't DML-writable
     * (common for custom geolocation fields). Falls back to __Latitude__s / __Longitude__s.
     */
    private static void setLocationField(
        SObject record,
        String fieldApiName,
        Double latitude,
        Double longitude,
        Boolean isInsert
    ) {
        if (record == null || String.isBlank(fieldApiName) || latitude == null || longitude == null) {
            return;
        }

        Schema.SObjectField compoundField = CACHE_FIELD_MAP != null ? CACHE_FIELD_MAP.get(fieldApiName) : null;
        Boolean wroteAny = false;

        if (compoundField != null) {
            Schema.DescribeFieldResult d = compoundField.getDescribe();
            Boolean canWriteCompound = isInsert ? d.isCreateable() : d.isUpdateable();
            if (canWriteCompound) {
                record.put(fieldApiName, Location.newInstance(latitude, longitude));
                wroteAny = true;
            }
        }

        if (!wroteAny && fieldApiName.endsWith('__c')) {
            String latFieldApiName = fieldApiName.substring(0, fieldApiName.length() - 3) + '__Latitude__s';
            String lonFieldApiName = fieldApiName.substring(0, fieldApiName.length() - 3) + '__Longitude__s';

            Schema.SObjectField latField = CACHE_FIELD_MAP != null ? CACHE_FIELD_MAP.get(latFieldApiName) : null;
            Schema.SObjectField lonField = CACHE_FIELD_MAP != null ? CACHE_FIELD_MAP.get(lonFieldApiName) : null;

            if (latField != null) {
                Schema.DescribeFieldResult ld = latField.getDescribe();
                Boolean canWriteLat = isInsert ? ld.isCreateable() : ld.isUpdateable();
                if (canWriteLat) {
                    record.put(latFieldApiName, latitude);
                    wroteAny = true;
                }
            }
            if (lonField != null) {
                Schema.DescribeFieldResult lod = lonField.getDescribe();
                Boolean canWriteLon = isInsert ? lod.isCreateable() : lod.isUpdateable();
                if (canWriteLon) {
                    record.put(lonFieldApiName, longitude);
                    wroteAny = true;
                }
            }
        }
    }

    /**
     * Returns an end-user-safe message (no stack trace / internal details).
     * Full technical details are logged server-side for troubleshooting.
     */
    private static String formatExceptionForClient(String prefix, Exception ex) {
        String safePrefix = String.isBlank(prefix) ? 'Operation failed' : prefix;
        logException(safePrefix, ex);
        return safePrefix + '. Please try again. If the problem persists, contact your administrator.';
    }

    private static void logException(String prefix, Exception ex) {
        if (ex == null) {
            System.debug(LoggingLevel.ERROR, prefix + ': Unknown exception (null)');
            return;
        }

        System.debug(
            LoggingLevel.ERROR,
            prefix + ': ' + ex.getTypeName() +
            ' (line ' + String.valueOf(ex.getLineNumber()) + ') ' +
            ex.getMessage() + '\n' +
            ex.getStackTraceString()
        );
    }

    // --- Schema-safe origin coordinate support (avoids hard-referencing fields that may not exist) ---

    private static List<GeocodeCache__c> queryExistingCaches(String originAddress, List<String> destinationAddresses) {
        // Always include required fields.
        List<String> fields = new List<String>{ 'Id', 'Origin_Address__c', 'Destination_Address__c' };

        // Optional origin coordinate fields (different orgs/package versions may store these differently).
        // Prefer geolocation subfields when present, else numeric lat/lon fields.
        List<String> optional = new List<String>{
            'Origin_Location__Latitude__s',
            'Origin_Location__Longitude__s',
            // If origin is stored in a custom geolocation field (Apex type: System.Location),
            // read the subfields instead of the compound field to avoid Location->Double assignment.
            'Origin_Location_Latitude__Latitude__s',
            'Origin_Location_Latitude__Longitude__s',
            'Origin_Location_Longitude__Latitude__s',
            'Origin_Location_Longitude__Longitude__s',
            'Origin_Latitude__c',
            'Origin_Longitude__c',
            'Origin_Lat__c',
            'Origin_Lng__c'
        };
        for (String f : optional) {
            if (CACHE_FIELD_MAP != null && CACHE_FIELD_MAP.containsKey(f)) {
                fields.add(f);
            }
        }

        String soql =
            'SELECT ' + String.join(fields, ', ') +
            ' FROM GeocodeCache__c' +
            ' WHERE Origin_Address__c = ' + quoteSoql(originAddress) +
            ' AND Destination_Address__c IN ' + toSoqlInList(destinationAddresses);

        return (List<GeocodeCache__c>) Database.query(soql);
    }

    private static LatLng extractOriginLatLng(SObject cacheRow) {
        if (cacheRow == null || CACHE_FIELD_MAP == null) {
            return null;
        }

        // 1) Geolocation subfields (if Origin_Location__c exists as a geolocation compound field)
        LatLng coreGeo = extractLatLngFromFields(cacheRow, 'Origin_Location__Latitude__s', 'Origin_Location__Longitude__s');
        if (coreGeo != null) return coreGeo;

        // 2) Alternate custom geolocation fields (still store a point; read subfields).
        LatLng customGeo = extractLatLngFromFields(cacheRow, 'Origin_Location_Latitude__Latitude__s', 'Origin_Location_Latitude__Longitude__s');
        if (customGeo != null) return customGeo;

        LatLng customGeo2 = extractLatLngFromFields(cacheRow, 'Origin_Location_Longitude__Latitude__s', 'Origin_Location_Longitude__Longitude__s');
        if (customGeo2 != null) return customGeo2;

        // 3) Numeric lat/lon fields (common fallback design)
        LatLng numeric = extractLatLngFromFields(cacheRow, 'Origin_Latitude__c', 'Origin_Longitude__c');
        if (numeric != null) return numeric;

        // 4) Alternate short names
        return extractLatLngFromFields(cacheRow, 'Origin_Lat__c', 'Origin_Lng__c');
    }

    private static LatLng getOriginLatLngFromAnyCacheRow(String originAddress) {
        if (String.isBlank(originAddress)) return null;
        // Pull a single cache row for this origin and extract origin lat/lng using schema-safe logic.
        List<GeocodeCache__c> rows = (List<GeocodeCache__c>) Database.query(
            'SELECT Id, Origin_Address__c, Destination_Address__c' +
            // optional fields will only be selected if present
            OPTIONAL_ORIGIN_FIELDS_SELECT +
            ' FROM GeocodeCache__c' +
            ' WHERE Origin_Address__c = ' + quoteSoql(originAddress) +
            ' ORDER BY LastModifiedDate DESC LIMIT 1'
        );
        if (rows.isEmpty()) return null;
        return extractOriginLatLng(rows[0]);
    }

    private static String quoteSoql(String value) {
        return value == null ? 'NULL' : '\'' + String.escapeSingleQuotes(value) + '\'';
    }

    private static String toSoqlInList(List<String> values) {
        if (values == null || values.isEmpty()) {
            // Empty IN lists are invalid SOQL; return a clause that matches nothing.
            return '(\'\')';
        }
        List<String> quoted = new List<String>();
        for (String v : values) {
            quoted.add(quoteSoql(v));
        }
        return '(' + String.join(quoted, ',') + ')';
    }

    private static String initOptionalOriginFieldsSelect() {
        List<String> optional = new List<String>();
        List<String> candidates = new List<String>{
            'Origin_Location__Latitude__s',
            'Origin_Location__Longitude__s',
            'Origin_Location_Latitude__Latitude__s',
            'Origin_Location_Latitude__Longitude__s',
            'Origin_Location_Longitude__Latitude__s',
            'Origin_Location_Longitude__Longitude__s',
            'Origin_Latitude__c',
            'Origin_Longitude__c',
            'Origin_Lat__c',
            'Origin_Lng__c'
        };
        for (String f : candidates) {
            if (CACHE_FIELD_MAP != null && CACHE_FIELD_MAP.containsKey(f)) {
                optional.add(f);
            }
        }
        return optional.isEmpty() ? '' : (', ' + String.join(optional, ', '));
    }

    private static LatLng extractLatLngFromFields(SObject row, String latFieldApiName, String lonFieldApiName) {
        if (row == null || CACHE_FIELD_MAP == null) return null;
        if (!CACHE_FIELD_MAP.containsKey(latFieldApiName) || !CACHE_FIELD_MAP.containsKey(lonFieldApiName)) return null;
        Object latVal = row.get(latFieldApiName);
        Object lonVal = row.get(lonFieldApiName);
        if (latVal instanceof Double && lonVal instanceof Double) {
            Double lat = (Double) latVal;
            Double lon = (Double) lonVal;
            return (lat != null && lon != null) ? new LatLng(lat, lon) : null;
        }
        return null;
    }

    private static void writeOriginLatLng(SObject record, Double lat, Double lon, Boolean isInsert) {
        if (record == null || lat == null || lon == null || CACHE_FIELD_MAP == null) {
            return;
        }

        // Prefer geolocation compound field when available.
        if (CACHE_FIELD_MAP.containsKey('Origin_Location__c')) {
            setLocationField(record, 'Origin_Location__c', lat, lon, isInsert);
            // If compound wasn't writable, setLocationField will try __Latitude__s/__Longitude__s automatically.
            return;
        }

        // If org incorrectly modeled lat/long as separate geolocation fields, write the point to either field.
        // (A geolocation field always stores both latitude and longitude.)
        if (CACHE_FIELD_MAP.containsKey('Origin_Location_Latitude__c')) {
            setLocationField(record, 'Origin_Location_Latitude__c', lat, lon, isInsert);
            return;
        }
        if (CACHE_FIELD_MAP.containsKey('Origin_Location_Longitude__c')) {
            setLocationField(record, 'Origin_Location_Longitude__c', lat, lon, isInsert);
            return;
        }

        // Otherwise try numeric fields.
        if (tryWriteNumericLatLng(record, 'Origin_Latitude__c', 'Origin_Longitude__c', lat, lon, isInsert)) {
            return;
        }
        tryWriteNumericLatLng(record, 'Origin_Lat__c', 'Origin_Lng__c', lat, lon, isInsert);
    }

    private static Boolean tryWriteNumericLatLng(
        SObject record,
        String latField,
        String lonField,
        Double lat,
        Double lon,
        Boolean isInsert
    ) {
        if (CACHE_FIELD_MAP == null || !CACHE_FIELD_MAP.containsKey(latField) || !CACHE_FIELD_MAP.containsKey(lonField)) {
            return false;
        }

        Schema.SObjectField latF = CACHE_FIELD_MAP.get(latField);
        Schema.SObjectField lonF = CACHE_FIELD_MAP.get(lonField);
        if (latF == null || lonF == null) return false;

        Schema.DescribeFieldResult latD = latF.getDescribe();
        Schema.DescribeFieldResult lonD = lonF.getDescribe();
        Boolean canWriteLat = isInsert ? latD.isCreateable() : latD.isUpdateable();
        Boolean canWriteLon = isInsert ? lonD.isCreateable() : lonD.isUpdateable();
        if (!canWriteLat || !canWriteLon) return false;

        record.put(latField, lat);
        record.put(lonField, lon);
        return true;
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
        if (accountId == null) {
            return null;
        }
        try {
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
            return parts.isEmpty() ? null : String.join(parts, ', ');
        } catch (Exception ex) {
            // Non-blocking fallback: allow caller to handle null/empty origin.
            return null;
        }
    }

    // --- Private data holders (keep all inner classes together for readability) ---
    private class LatLng {
        Double lat;
        Double lng;
        LatLng(Double lat, Double lng) {
            this.lat = lat;
            this.lng = lng;
        }
    }

    private class CacheContext {
        Double originLatitude;
        Double originLongitude;
    }
}
