@IsTest
private class ParentGuardianControllerTest {
    private static final String RELATIONSHIP_OBJECT = 'Contact_Relationship__c';
    private static final List<String> REQUIRED_RELATIONSHIP_FIELDS =
        new List<String>{
            'Primary_Contact__c',
            'Related_Contact__c',
            'Account__c',
            'Relationship_Type__c',
            'Is_Active__c',
            'End_Date__c'
        };

    private static Id getPersonAccountRecordTypeId() {
        Schema.RecordTypeInfo recordTypeInfo =
            Schema.SObjectType.Account
                .getRecordTypeInfosByDeveloperName()
                .get('PersonAccount');

        System.assertNotEquals(
            null,
            recordTypeInfo,
            'ParentGuardianController requires a PersonAccount record type.'
        );
        return recordTypeInfo.getRecordTypeId();
    }

    private static Map<String, Schema.SObjectField> getRelationshipFields() {
        Schema.SObjectType relationshipType =
            Schema.getGlobalDescribe().get(RELATIONSHIP_OBJECT);
        if (relationshipType == null) {
            return new Map<String, Schema.SObjectField>();
        }
        return relationshipType.getDescribe().fields.getMap();
    }

    private static Boolean hasRequiredRelationshipSchema() {
        Map<String, Schema.SObjectField> fields = getRelationshipFields();
        for (String fieldName : REQUIRED_RELATIONSHIP_FIELDS) {
            if (!fields.containsKey(fieldName)) {
                return false;
            }
        }
        return true;
    }

    private static String getRelationshipTypeValue() {
        Map<String, Schema.SObjectField> fields = getRelationshipFields();
        if (fields.containsKey('Relationship_Type__c')) {
            Schema.DescribeFieldResult relationshipType =
                fields.get('Relationship_Type__c').getDescribe();
            if (relationshipType.getType() == Schema.DisplayType.Picklist) {
                for (Schema.PicklistEntry entry :
                        relationshipType.getPicklistValues()) {
                    if (entry.isActive()) {
                        return entry.getValue();
                    }
                }
            }
        }
        return 'Parent/Guardian';
    }

    private static Account createPersonAccount(
            String firstName,
            String lastName,
            Date birthdate,
            String homePhone,
            String mobilePhone,
            String street,
            String city,
            String postalCode) {
        Account personAccount = new Account(
            RecordTypeId = getPersonAccountRecordTypeId(),
            FirstName = firstName,
            LastName = lastName,
            PersonBirthdate = birthdate,
            PersonHomePhone = homePhone,
            PersonMobilePhone = mobilePhone,
            BillingStreet = street,
            BillingCity = city,
            BillingPostalCode = postalCode
        );
        insert personAccount;

        Account created = [
            SELECT Id,
                   Name,
                   FirstName,
                   LastName,
                   PersonContactId,
                   PersonBirthdate,
                   PersonHomePhone,
                   PersonMobilePhone,
                   BillingStreet,
                   BillingCity,
                   BillingState,
                   BillingPostalCode
            FROM Account
            WHERE Id = :personAccount.Id
        ];

        System.assertNotEquals(
            null,
            created.PersonContactId,
            'Inserted Person Account should have a backing Contact.'
        );
        return created;
    }

    @IsTest
    static void getMinorStatusReturnsAlertForMinorWithoutGuardian() {
        Account adult = createPersonAccount(
            'Adam',
            'Adult',
            Date.today().addYears(-25),
            null,
            null,
            null,
            null,
            null
        );

        Map<String, Object> adultStatus =
            ParentGuardianController.getMinorStatus(adult.Id);

        System.assertEquals(false, adultStatus.get('isMinor'));
        System.assertEquals(false, adultStatus.get('hasParentGuardian'));
        System.assertEquals(false, adultStatus.get('showAlert'));

        if (!hasRequiredRelationshipSchema()) {
            return;
        }

        Account minor = createPersonAccount(
            'Mina',
            'Minor',
            Date.today().addYears(-10),
            null,
            null,
            null,
            null,
            null
        );

        Test.startTest();
        Map<String, Object> minorStatus =
            ParentGuardianController.getMinorStatus(minor.Id);
        Test.stopTest();

        System.assertEquals(true, minorStatus.get('isMinor'));
        System.assertEquals(false, minorStatus.get('hasParentGuardian'));
        System.assertEquals(true, minorStatus.get('showAlert'));
    }

    @IsTest
    static void searchPersonAccountsReturnsMatchingRecords() {
        Account guardian = createPersonAccount(
            'Sally',
            'SearchGuardian',
            Date.today().addYears(-30),
            null,
            null,
            null,
            null,
            null
        );

        Test.startTest();
        List<Account> searchResults =
            ParentGuardianController.searchPersonAccounts('SearchGuardian');
        Test.stopTest();

        Set<Id> searchResultIds = new Set<Id>();
        for (Account accountRecord : searchResults) {
            searchResultIds.add(accountRecord.Id);
        }
        System.assert(
            searchResultIds.contains(guardian.Id),
            'Expected person account search to return the matching account.'
        );
    }

    @IsTest
    static void addSearchListHistoryAndRemoveAssociation() {
        if (!hasRequiredRelationshipSchema()) {
            return;
        }

        Account minor = createPersonAccount(
            'Chris',
            'Child',
            Date.today().addYears(-12),
            null,
            null,
            null,
            null,
            null
        );
        Account guardian = createPersonAccount(
            'Gina',
            'Guardian',
            Date.today().addYears(-40),
            null,
            '555-2222',
            '10 Oak St',
            'Springfield',
            '12345'
        );
        String role = getRelationshipTypeValue();

        Test.startTest();
        ParentGuardianController.addAssociation(minor.Id, guardian.Id, role);
        Test.stopTest();

        SObject relation = Database.query(
            'SELECT Id, Primary_Contact__c, Related_Contact__c, Account__c, ' +
            'Relationship_Type__c, Is_Active__c, End_Date__c ' +
            'FROM Contact_Relationship__c ' +
            'WHERE Primary_Contact__c = \'' +
                String.escapeSingleQuotes(String.valueOf(minor.PersonContactId)) +
                '\' ' +
            'AND Related_Contact__c = \'' +
                String.escapeSingleQuotes(String.valueOf(guardian.PersonContactId)) +
                '\' ' +
            'LIMIT 1'
        );
        System.assertEquals(minor.PersonContactId, relation.get('Primary_Contact__c'));
        System.assertEquals(guardian.PersonContactId, relation.get('Related_Contact__c'));
        System.assertEquals(minor.Id, relation.get('Account__c'));
        System.assertEquals(role, relation.get('Relationship_Type__c'));
        System.assertEquals(true, relation.get('Is_Active__c'));
        System.assertEquals(null, relation.get('End_Date__c'));

        Map<String, Object> minorStatus =
            ParentGuardianController.getMinorStatus(minor.Id);
        System.assertEquals(true, minorStatus.get('isMinor'));
        System.assertEquals(true, minorStatus.get('hasParentGuardian'));
        System.assertEquals(false, minorStatus.get('showAlert'));

        List<Account> searchResults =
            ParentGuardianController.searchPersonAccounts('Guardian');
        Set<Id> searchResultIds = new Set<Id>();
        for (Account accountRecord : searchResults) {
            searchResultIds.add(accountRecord.Id);
        }
        System.assert(
            searchResultIds.contains(guardian.Id),
            'Expected person account search to return the guardian account.'
        );

        Map<String, Object> associations =
            ParentGuardianController.getAssociations(minor.Id);
        System.assertEquals(1, associations.get('totalCount'));
        List<Map<String, Object>> associationRows =
            (List<Map<String, Object>>) associations.get('associations');
        System.assertEquals(1, associationRows.size());

        Map<String, Object> associationRow = associationRows[0];
        System.assertEquals((Id) relation.get('Id'), associationRow.get('Id'));
        System.assertEquals(role, associationRow.get('Role'));
        System.assertEquals(guardian.Name, associationRow.get('Name'));
        System.assertEquals(
            String.valueOf(guardian.PersonBirthdate),
            associationRow.get('DOB')
        );
        System.assertEquals('555-2222', associationRow.get('Phone'));
        System.assertEquals(
            '10 Oak St, Springfield, 12345',
            associationRow.get('Address')
        );

        List<Map<String, Object>> activeHistory =
            ParentGuardianController.getHistory(minor.Id);
        System.assertEquals(1, activeHistory.size());
        System.assertEquals('Added', activeHistory[0].get('ActionPerformed'));
        System.assertEquals(guardian.Name, activeHistory[0].get('Name'));

        ParentGuardianController.removeAssociation((Id) relation.get('Id'));

        SObject removedRelation = Database.query(
            'SELECT Is_Active__c, End_Date__c ' +
            'FROM Contact_Relationship__c ' +
            'WHERE Id = \'' +
                String.escapeSingleQuotes(String.valueOf(relation.get('Id'))) +
                '\''
        );
        System.assertEquals(false, removedRelation.get('Is_Active__c'));
        System.assertEquals(Date.today(), removedRelation.get('End_Date__c'));

        Map<String, Object> associationsAfterRemoval =
            ParentGuardianController.getAssociations(minor.Id);
        System.assertEquals(0, associationsAfterRemoval.get('totalCount'));

        List<Map<String, Object>> fullHistory =
            ParentGuardianController.getHistory(minor.Id);
        Set<String> actions = new Set<String>();
        for (Map<String, Object> historyRow : fullHistory) {
            actions.add((String) historyRow.get('ActionPerformed'));
        }
        System.assertEquals(2, fullHistory.size());
        System.assert(actions.contains('Added'));
        System.assert(actions.contains('Removed'));
    }

    @IsTest
    static void addAssociationRejectsDuplicateActiveRelationship() {
        if (!hasRequiredRelationshipSchema()) {
            return;
        }

        Account minor = createPersonAccount(
            'Dee',
            'DuplicateChild',
            Date.today().addYears(-9),
            null,
            null,
            null,
            null,
            null
        );
        Account guardian = createPersonAccount(
            'Pat',
            'DuplicateGuardian',
            Date.today().addYears(-35),
            null,
            null,
            null,
            null,
            null
        );
        String role = getRelationshipTypeValue();
        ParentGuardianController.addAssociation(minor.Id, guardian.Id, role);

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ParentGuardianController.addAssociation(minor.Id, guardian.Id, role);
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(
            exceptionThrown,
            'Adding the same active guardian twice should throw an exception.'
        );
    }

    @IsTest
    static void createAndAssociateCreatesPersonAccountAndRelationship() {
        if (!hasRequiredRelationshipSchema()) {
            return;
        }

        Account minor = createPersonAccount(
            'Casey',
            'CreateChild',
            Date.today().addYears(-8),
            null,
            null,
            null,
            null,
            null
        );
        String role = getRelationshipTypeValue();

        Test.startTest();
        ParentGuardianController.createAndAssociate(
            minor.Id,
            'New',
            'Guardian',
            Date.today().addYears(-32),
            '555-3333',
            '50 Elm St',
            'Riverside',
            null,
            '99999',
            role
        );
        Test.stopTest();

        Account newGuardian = [
            SELECT Id,
                   FirstName,
                   LastName,
                   PersonContactId,
                   PersonBirthdate,
                   PersonHomePhone,
                   BillingStreet,
                   BillingCity,
                   BillingPostalCode
            FROM Account
            WHERE FirstName = 'New'
            AND LastName = 'Guardian'
            LIMIT 1
        ];
        System.assertEquals(Date.today().addYears(-32), newGuardian.PersonBirthdate);
        System.assertEquals('555-3333', newGuardian.PersonHomePhone);
        System.assertEquals('50 Elm St', newGuardian.BillingStreet);
        System.assertEquals('Riverside', newGuardian.BillingCity);
        System.assertEquals('99999', newGuardian.BillingPostalCode);

        SObject relation = Database.query(
            'SELECT Primary_Contact__c, Related_Contact__c, Account__c, ' +
            'Relationship_Type__c, Is_Active__c ' +
            'FROM Contact_Relationship__c ' +
            'WHERE Primary_Contact__c = \'' +
                String.escapeSingleQuotes(String.valueOf(minor.PersonContactId)) +
                '\' ' +
            'AND Related_Contact__c = \'' +
                String.escapeSingleQuotes(String.valueOf(newGuardian.PersonContactId)) +
                '\' ' +
            'LIMIT 1'
        );
        System.assertEquals(minor.PersonContactId, relation.get('Primary_Contact__c'));
        System.assertEquals(newGuardian.PersonContactId, relation.get('Related_Contact__c'));
        System.assertEquals(minor.Id, relation.get('Account__c'));
        System.assertEquals(role, relation.get('Relationship_Type__c'));
        System.assertEquals(true, relation.get('Is_Active__c'));
    }
}
