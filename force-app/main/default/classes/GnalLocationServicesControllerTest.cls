@IsTest
private class GnalLocationServicesControllerTest {

    @IsTest
    static void createOrIncrement_createsOnceAndIncrements() {
        Account a = new Account(Name = 'Test Account');
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
        System.assertEquals(r1.locationServiceId, r2.locationServiceId);
        System.assertEquals(1, r1.searchCount);
        System.assertEquals(2, r2.searchCount);

        Location_Services__c saved = [
            SELECT Search_Count__c, Current_Location__c, Final_Origin_Address__c, Case__c
            FROM Location_Services__c
            WHERE Id = :r1.locationServiceId
            LIMIT 1
        ];
        System.assertEquals(c.Id, saved.Case__c);
        System.assertEquals('123 Main St', saved.Current_Location__c);
        System.assertEquals('123 Main St', saved.Final_Origin_Address__c);
        System.assertEquals(2, Integer.valueOf(saved.Search_Count__c));
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

