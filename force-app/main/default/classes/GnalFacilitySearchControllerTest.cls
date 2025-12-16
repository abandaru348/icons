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
}
