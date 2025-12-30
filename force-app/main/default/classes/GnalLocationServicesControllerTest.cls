@IsTest
private class GnalLocationServicesControllerTest {

    @IsTest
    static void createOrIncrement_createsOnceAndIncrements() {
        Account a = new Account(Name = 'Test Person');
        insert a;
        Case c = new Case(Subject = 'Test', Status = 'New', Origin = 'Phone', AccountId = a.Id);
        insert c;

        Test.startTest();
        GnalLocationServicesController.LocationServiceUpsertResult r1 =
            GnalLocationServicesController.createOrIncrementLocationService(c.Id, '123 Main St');
        GnalLocationServicesController.LocationServiceUpsertResult r2 =
            GnalLocationServicesController.createOrIncrementLocationService(c.Id, '123 Main St');
        Test.stopTest();

        System.assertNotEquals(null, r1.locationServiceId);
        System.assertEquals(r1.locationServiceId, r2.locationServiceId, 'Should not create duplicate record');
        System.assertEquals(1, r1.searchCount);
        System.assertEquals(2, r2.searchCount);
    }

    @IsTest
    static void getDefaultCurrentLocationForCase_returnsNullWhenNoAccount() {
        Case c = new Case(Subject = 'No Account', Status = 'New', Origin = 'Phone');
        insert c;
        Test.startTest();
        String addr = GnalLocationServicesController.getDefaultCurrentLocationForCase(c.Id);
        Test.stopTest();
        System.assertEquals(null, addr);
    }
}

