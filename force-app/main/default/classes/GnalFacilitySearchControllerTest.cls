@IsTest
private class GnalFacilitySearchControllerTest {
    private static void setFieldIfExists(SObject record, String fieldApiName, Object value) {
        if (record == null || String.isBlank(fieldApiName)) return;
        Map<String, Schema.SObjectField> fields = record.getSObjectType().getDescribe().fields.getMap();
        if (fields != null && fields.containsKey(fieldApiName)) {
            record.put(fieldApiName, value);
        }
    }

    private static void setGeo(SObject record, String fieldApiName, Decimal lat, Decimal lon) {
        if (record == null || String.isBlank(fieldApiName) || lat == null || lon == null) return;
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.GeocodeCache__c.fields.getMap();
        if (fields == null) return;

        Schema.SObjectField f = fields.get(fieldApiName);
        if (f != null && f.getDescribe().isCreateable()) {
            record.put(fieldApiName, Location.newInstance((Double) lat, (Double) lon));
            return;
        }

        if (fieldApiName.endsWith('__c')) {
            String latField = fieldApiName.substring(0, fieldApiName.length() - 3) + '__Latitude__s';
            String lonField = fieldApiName.substring(0, fieldApiName.length() - 3) + '__Longitude__s';
            Schema.SObjectField lf = fields.get(latField);
            Schema.SObjectField lof = fields.get(lonField);
            if (lf != null && lf.getDescribe().isCreateable()) record.put(latField, (Double) lat);
            if (lof != null && lof.getDescribe().isCreateable()) record.put(lonField, (Double) lon);
        }
    }

    private static String formatAddress(String street, String city, String state, String postal, String country) {
        List<String> parts = new List<String>();
        if (!String.isBlank(street)) parts.add(street);
        if (!String.isBlank(city)) parts.add(city);
        if (!String.isBlank(state)) parts.add(state);
        if (!String.isBlank(postal)) parts.add(postal);
        if (!String.isBlank(country)) parts.add(country);
        return String.join(parts, ', ');
    }

    private class GoogleMockMany implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);

            // Be endpoint-agnostic: org labels may use real Google endpoints.
            if (req.getMethod() == 'GET') {
                res.setBody('{' +
                    '"results":[{' +
                        '"geometry":{"location":{"lat":30.2672,"lng":-97.7431}}' +
                    '}],' +
                    '"status":"OK"' +
                '}');
                return res;
            }

            if (req.getMethod() == 'POST') {
                // Build a response entry per destination in request body.
                Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(req.getBody());
                List<Object> dests = (List<Object>) body.get('destinations');
                Integer n = dests == null ? 0 : dests.size();
                List<Object> payload = new List<Object>();
                for (Integer i = 0; i < n; i++) {
                    payload.add(new Map<String, Object>{
                        'originIndex' => 0.0,
                        'destinationIndex' => (Double) i,
                        'status' => 'OK',
                        'distanceMeters' => (Double) (1609.344 * (i + 1)),
                        'duration' => '600s'
                    });
                }
                res.setBody(JSON.serialize(payload));
                return res;
            }

            res.setStatusCode(404);
            res.setBody('Not Found');
            return res;
        }
    }

    @IsTest
    static void getAccountBillingAddress_returnsJoinedAddress() {
        Account a = new Account(
            Name = 'Test Account',
            BillingStreet = '123 Main St',
            BillingCity = 'Austin',
            BillingPostalCode = '78701'
        );
        // State/Country picklists enabled: use BillingStateCode.
        setFieldIfExists(a, 'BillingCountryCode', 'US');
        setFieldIfExists(a, 'BillingStateCode', 'TX');
        insert a;

        Test.startTest();
        String result = GnalFacilitySearchController.getAccountBillingAddress(a.Id);
        Test.stopTest();

        // Controller uses BillingStateCode. Country may be auto-derived from BillingCountryCode depending on settings.
        String base = '123 Main St, Austin, TX, 78701';
        System.assert(
            result == base || result == (base + ', United States'),
            'Unexpected billing address: ' + result
        );
    }

    @IsTest
    static void getAccountBillingAddress_nullAccount_returnsNull() {
        Test.startTest();
        String result = GnalFacilitySearchController.getAccountBillingAddress(null);
        Test.stopTest();

        System.assertEquals(null, result);
    }

    @IsTest
    static void getAccountBillingAddress_nonexistentId_returnsNull() {
        // Cover the internal try/catch branch when the Account query fails.
        Id fakeAccountId = (Id) '001000000000000AAA';
        Test.startTest();
        String result = GnalFacilitySearchController.getAccountBillingAddress(fakeAccountId);
        Test.stopTest();
        System.assertEquals(null, result);
    }

    @IsTest
    static void getLatestCaseOriginAddress_internalUserWithoutAccount_returnsNull() {
        // Most internal users do not have User.AccountId populated.
        // The controller should safely return null rather than throwing.
        Test.startTest();
        String origin = GnalFacilitySearchController.getLatestCaseOriginAddress();
        Test.stopTest();

        System.assertEquals(null, origin);
    }

    @IsTest
    static void getLatestCaseOriginAddress_accountNameFallback_returnsValue() {
        // Covers the fallback branch in getLatestCaseOriginAddress() where it queries
        // Case by Account.Name = running User.Name.
        String userName = UserInfo.getName();
        Account a = new Account(Name = userName);
        insert a;

        Case c = new Case(
            AccountId = a.Id,
            Origin = 'Phone',
            Status = 'New'
        );
        // GNAL origin fields may not exist in all orgs (QA sandboxes can lag metadata).
        // If absent, controller should return null and the test should not fail.
        Map<String, Schema.SObjectField> caseFields = Schema.SObjectType.Case.fields.getMap();
        Boolean wroteAny = false;
        if (caseFields != null && caseFields.containsKey('GNAL_Origin_Location__c')) {
            Schema.SObjectField f = caseFields.get('GNAL_Origin_Location__c');
            Schema.DescribeFieldResult d = f != null ? f.getDescribe() : null;
            if (d != null && d.getType() != Schema.DisplayType.Address) {
                c.put('GNAL_Origin_Location__c', 'From Case GNAL Origin');
                wroteAny = true;
            }
        }
        if (!wroteAny && caseFields != null && caseFields.containsKey('GNAL_Origin_Location__Street__s')) {
            c.put('GNAL_Origin_Location__Street__s', 'From Case GNAL Origin');
            wroteAny = true;
        }
        insert c;

        Test.startTest();
        String origin = GnalFacilitySearchController.getLatestCaseOriginAddress();
        Test.stopTest();

        System.assertEquals(wroteAny ? 'From Case GNAL Origin' : null, origin);
    }

    @IsTest
    static void getLatestCaseOriginAddressForAccount_noCases_returnsNull() {
        Account a = new Account(Name = 'No Case Account');
        insert a;

        Test.startTest();
        String origin = GnalFacilitySearchController.getLatestCaseOriginAddressForAccount(a.Id);
        Test.stopTest();

        System.assertEquals(null, origin);
    }

    @IsTest
    static void getLatestCaseOriginAddressForAccount_prefersStrictMatch() {
        Account a = new Account(Name = 'Case Account');
        insert a;

        // Fallback-eligible case (GNAL populated but Origin/Status not the strict values)
        Case cFallback = new Case(
            AccountId = a.Id,
            Origin = 'Email',
            Status = 'Working'
        );
        Map<String, Schema.SObjectField> caseFields = Schema.SObjectType.Case.fields.getMap();
        Boolean wroteAny = false;
        if (caseFields != null && caseFields.containsKey('GNAL_Origin_Location__c')) {
            Schema.SObjectField f = caseFields.get('GNAL_Origin_Location__c');
            Schema.DescribeFieldResult d = f != null ? f.getDescribe() : null;
            if (d != null && d.getType() != Schema.DisplayType.Address) {
                cFallback.put('GNAL_Origin_Location__c', 'Fallback Address');
                wroteAny = true;
            }
        }
        if (!wroteAny && caseFields != null && caseFields.containsKey('GNAL_Origin_Location__Street__s')) {
            cFallback.put('GNAL_Origin_Location__Street__s', 'Fallback Address');
            wroteAny = true;
        }
        insert cFallback;

        // Strict match case (should win even if older/newer ordering differs by CreatedDate)
        Case cStrict = new Case(
            AccountId = a.Id,
            Origin = 'Phone',
            Status = 'New'
        );
        Boolean wroteStrict = false;
        if (caseFields != null && caseFields.containsKey('GNAL_Origin_Location__c')) {
            Schema.SObjectField f2 = caseFields.get('GNAL_Origin_Location__c');
            Schema.DescribeFieldResult d2 = f2 != null ? f2.getDescribe() : null;
            if (d2 != null && d2.getType() != Schema.DisplayType.Address) {
                cStrict.put('GNAL_Origin_Location__c', 'Strict Address');
                wroteStrict = true;
            }
        }
        if (!wroteStrict && caseFields != null && caseFields.containsKey('GNAL_Origin_Location__Street__s')) {
            cStrict.put('GNAL_Origin_Location__Street__s', 'Strict Address');
            wroteStrict = true;
        }
        insert cStrict;

        Test.startTest();
        String origin = GnalFacilitySearchController.getLatestCaseOriginAddressForAccount(a.Id);
        Test.stopTest();

        // If GNAL fields are missing in this org, controller will (correctly) return null.
        System.assertEquals(wroteStrict ? 'Strict Address' : null, origin);
    }

    @IsTest
    static void getLatestCaseOriginAddressForAccount_fallbacksWhenPicklistsDiffer() {
        Account a = new Account(Name = 'Case Fallback Account');
        insert a;
        Map<String, Schema.SObjectField> caseFields = Schema.SObjectType.Case.fields.getMap();

        // No strict match, but GNAL origin is populated.
        Case c = new Case(
            AccountId = a.Id,
            Origin = 'Web',
            Status = 'Closed'
        );
        Boolean wroteAny = false;
        if (caseFields != null && caseFields.containsKey('GNAL_Origin_Location__c')) {
            Schema.SObjectField f = caseFields.get('GNAL_Origin_Location__c');
            Schema.DescribeFieldResult d = f != null ? f.getDescribe() : null;
            if (d != null && d.getType() != Schema.DisplayType.Address) {
                c.put('GNAL_Origin_Location__c', 'Only Available Address');
                wroteAny = true;
            }
        }
        if (!wroteAny && caseFields != null && caseFields.containsKey('GNAL_Origin_Location__Street__s')) {
            c.put('GNAL_Origin_Location__Street__s', 'Only Available Address');
            wroteAny = true;
        }
        insert c;

        Test.startTest();
        String origin = GnalFacilitySearchController.getLatestCaseOriginAddressForAccount(a.Id);
        Test.stopTest();

        System.assertEquals(wroteAny ? 'Only Available Address' : null, origin);
    }

    @IsTest
    static void findNearestFacilitiesWithRadius_cacheHit_returnsResults() {
        // Be resilient if the controller unexpectedly needs to warm origin coords (QA schema differences).
        Test.setMock(HttpCalloutMock.class, new GoogleMockMany());

        OperatingHours oh = new OperatingHours(
            Name = 'Test Hours',
            TimeZone = 'America/Chicago'
        );
        insert oh;

        ServiceTerritory st = new ServiceTerritory(
            Name = 'Facility A',
            IsActive = true,
            OperatingHoursId = oh.Id,
            Street = '1 Facility Way',
            City = 'Austin',
            PostalCode = '78701'
        );
        setFieldIfExists(st, 'CountryCode', 'US');
        setFieldIfExists(st, 'StateCode', 'TX');
        insert st;

        // Re-query for formatted address fields.
        ServiceTerritory stored = [
            SELECT Street, City, State, PostalCode, Country
            FROM ServiceTerritory
            WHERE Id = :st.Id
            LIMIT 1
        ];
        String destAddress = formatAddress(stored.Street, stored.City, stored.State, stored.PostalCode, stored.Country);
        String originAddress = '100 Origin St, Austin, TX 78701';

        GeocodeCache__c cache = new GeocodeCache__c();
        cache.Name = 'Cache-1';
        cache.Origin_Address__c = originAddress;
        cache.Destination_Address__c = destAddress;
        cache.Distance_Miles__c = 3;
        cache.Distance_Meters__c = 4828;
        cache.Travel_Time_Minutes__c = 12;

        setGeo(cache, 'Destination_Location__c', 30.2672, -97.7431);
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.GeocodeCache__c.fields.getMap();
        if (fields != null && fields.containsKey('Origin_Location__c')) {
            setGeo(cache, 'Origin_Location__c', 30.2672, -97.7431);
        } else if (fields != null && fields.containsKey('Origin_Location_Latitude__c')) {
            setGeo(cache, 'Origin_Location_Latitude__c', 30.2672, -97.7431);
        } else if (fields != null && fields.containsKey('Origin_Latitude__c') && fields.containsKey('Origin_Longitude__c')) {
            cache.put('Origin_Latitude__c', 30.2672);
            cache.put('Origin_Longitude__c', -97.7431);
        }
        insert cache;

        Test.startTest();
        List<Map<String, Object>> results =
            GnalFacilitySearchController.findNearestFacilitiesWithRadius(null, originAddress, 5);
        Test.stopTest();

        System.assertNotEquals(null, results);
        System.assertEquals(true, results.size() >= 1, 'Should return at least one cached facility');
    }

    @IsTest
    static void findNearestFacilitiesWithRadius_noTerritoryAddresses_throws() {
        OperatingHours oh = new OperatingHours(
            Name = 'Hours No Address',
            TimeZone = 'America/Chicago'
        );
        insert oh;

        ServiceTerritory st = new ServiceTerritory(
            Name = 'Facility No Address',
            IsActive = true,
            OperatingHoursId = oh.Id
        );
        insert st;

        Boolean threw = false;
        try {
            Test.startTest();
            GnalFacilitySearchController.findNearestFacilitiesWithRadius(null, 'Some Origin', 5);
        } catch (Exception ex) {
            threw = true;
        } finally {
            Test.stopTest();
        }
        System.assertEquals(true, threw);
    }

    // -------------------------
    // Added tests (minimal additions) to raise coverage.
    // -------------------------

    @IsTest
    static void getCaseAccountId_null_returnsNull() {
        Test.startTest();
        Id out = GnalFacilitySearchController.getCaseAccountId(null);
        Test.stopTest();
        System.assertEquals(null, out);
    }

    @IsTest
    static void getCaseAccountId_returnsAccountId() {
        Account a = new Account(Name = 'Acct');
        insert a;
        Case c = new Case(Subject = 'Test', Status = 'New', Origin = 'Phone', AccountId = a.Id);
        insert c;

        Test.startTest();
        Id out = GnalFacilitySearchController.getCaseAccountId(c.Id);
        Test.stopTest();
        System.assertEquals(a.Id, out);
    }

    @IsTest
    static void getCaseBillingAddress_null_returnsNull() {
        Test.startTest();
        String out = GnalFacilitySearchController.getCaseBillingAddress(null);
        Test.stopTest();
        System.assertEquals(null, out);
    }

    @IsTest
    static void getCaseBillingAddress_caseWithNoAccount_returnsNull() {
        Case c = new Case(Subject = 'No Account', Status = 'New', Origin = 'Phone');
        insert c;
        Test.startTest();
        String out = GnalFacilitySearchController.getCaseBillingAddress(c.Id);
        Test.stopTest();
        System.assertEquals(null, out);
    }

    @IsTest
    static void getCaseBillingAddress_returnsBillingAddress() {
        Account a = new Account(
            Name = 'Billing Acct',
            BillingStreet = '500 Main St',
            BillingCity = 'Austin',
            BillingPostalCode = '78701'
        );
        setFieldIfExists(a, 'BillingStateCode', 'TX');
        setFieldIfExists(a, 'BillingCountryCode', 'US');
        setFieldIfExists(a, 'BillingCountry', 'United States');
        insert a;

        Case c = new Case(Subject = 'Test', Status = 'New', Origin = 'Phone', AccountId = a.Id);
        insert c;

        Test.startTest();
        String out = GnalFacilitySearchController.getCaseBillingAddress(c.Id);
        Test.stopTest();

        System.assertNotEquals(null, out);
        System.assert(out.contains('500 Main St'));
    }

    @IsTest
    static void findFacilitiesFromCacheWithRadius_trimsOrigin_andReturnsRows_inTests() {
        String origin = 'Trim Me';
        insert new GeocodeCache__c(
            Name = 'TrimCache',
            Origin_Address__c = origin,
            Destination_Address__c = 'Dest',
            Distance_Miles__c = 1,
            Distance_Meters__c = 1609,
            Travel_Time_Minutes__c = 5
        );

        Test.startTest();
        List<Map<String, Object>> results = GnalFacilitySearchController.findFacilitiesFromCacheWithRadius('  ' + origin + '  ', 5);
        Test.stopTest();

        System.assertNotEquals(null, results);
        System.assertEquals(true, results.size() >= 1);
    }
}

