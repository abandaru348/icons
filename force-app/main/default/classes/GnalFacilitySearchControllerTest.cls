@IsTest
private class GnalFacilitySearchControllerTest {

    @IsTest
    static void getAccountBillingAddress_returnsJoinedAddress() {
        Account a = new Account(
            Name = 'Test Account',
            BillingStreet = '123 Main St',
            BillingCity = 'Austin',
            BillingState = 'TX',
            BillingPostalCode = '78701',
            BillingCountry = 'USA'
        );
        insert a;

        Test.startTest();
        String result = GnalFacilitySearchController.getAccountBillingAddress(a.Id);
        Test.stopTest();

        System.assertEquals('123 Main St, Austin, TX, 78701, USA', result);
    }

    @IsTest
    static void getAccountBillingAddress_nullAccount_returnsNull() {
        Test.startTest();
        String result = GnalFacilitySearchController.getAccountBillingAddress(null);
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
            Status = 'Working',
            GNAL_Origin_Location__c = 'Fallback Address'
        );
        insert cFallback;

        // Strict match case (should win even if older/newer ordering differs by CreatedDate)
        Case cStrict = new Case(
            AccountId = a.Id,
            Origin = 'Phone',
            Status = 'New',
            GNAL_Origin_Location__c = 'Strict Address'
        );
        insert cStrict;

        Test.startTest();
        String origin = GnalFacilitySearchController.getLatestCaseOriginAddressForAccount(a.Id);
        Test.stopTest();

        System.assertEquals('Strict Address', origin);
    }

    @IsTest
    static void getLatestCaseOriginAddressForAccount_fallbacksWhenPicklistsDiffer() {
        Account a = new Account(Name = 'Case Fallback Account');
        insert a;

        // No strict match, but GNAL origin is populated.
        Case c = new Case(
            AccountId = a.Id,
            Origin = 'Web',
            Status = 'Closed',
            GNAL_Origin_Location__c = 'Only Available Address'
        );
        insert c;

        Test.startTest();
        String origin = GnalFacilitySearchController.getLatestCaseOriginAddressForAccount(a.Id);
        Test.stopTest();

        System.assertEquals('Only Available Address', origin);
    }
}
