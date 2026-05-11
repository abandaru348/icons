public class ParentGuardianController {
    private static final String RELATIONSHIP_OBJECT = 'Contact_Relationship__c';

    private class RelationshipSchema {
        String objectName;
        String primaryContactField;
        String relatedContactField;
        String accountField;
        String roleField;
        String activeField;
        String endDateField;

        Boolean hasContactFields() {
            return String.isNotBlank(objectName)
                && String.isNotBlank(primaryContactField)
                && String.isNotBlank(relatedContactField);
        }
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getMinorStatus(Id accountId) {
        Account acc = [
            SELECT PersonBirthdate, PersonContactId
            FROM Account
            WHERE Id = :accountId
        ];

        Boolean isMinor = false;
        Boolean hasParentGuardian = false;

        if (acc.PersonBirthdate != null) {
            Integer age = acc.PersonBirthdate.monthsBetween(Date.today()) / 12;
            isMinor = age < 18;
        }

        RelationshipSchema relSchema = getRelationshipSchema();
        if (isMinor && acc.PersonContactId != null && relSchema.hasContactFields()) {
            Id primaryContactId = acc.PersonContactId;
            String soql =
                'SELECT Id FROM ' + relSchema.objectName +
                ' WHERE ' + relSchema.primaryContactField + ' = :primaryContactId';
            if (String.isNotBlank(relSchema.activeField)) {
                soql += ' AND ' + relSchema.activeField + ' = true';
            }
            soql += ' LIMIT 1';

            hasParentGuardian = !Database.query(soql).isEmpty();
        }

        Map<String, Object> result = new Map<String, Object>();
        result.put('isMinor', isMinor);
        result.put('hasParentGuardian', hasParentGuardian);
        result.put('showAlert', isMinor && !hasParentGuardian);
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<Account> searchPersonAccounts(String searchTerm) {
        String search = '%' + String.valueOf(searchTerm) + '%';
        return [
            SELECT Id, Name, FirstName, LastName, PersonContactId,
                   PersonBirthdate,
                   BillingStreet, BillingCity,
                   BillingState, BillingPostalCode,
                   PersonHomePhone, PersonMobilePhone
            FROM Account
            WHERE IsPersonAccount = true
            AND Name LIKE :search
            LIMIT 10
        ];
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getAssociations(Id minorAccountId) {
        Account minorAcc = [
            SELECT PersonContactId
            FROM Account
            WHERE Id = :minorAccountId
        ];

        List<Map<String, Object>> flatList = new List<Map<String, Object>>();
        RelationshipSchema relSchema = getRelationshipSchema();
        if (minorAcc.PersonContactId == null || !relSchema.hasContactFields()) {
            return associationsResult(flatList);
        }

        Id primaryContactId = minorAcc.PersonContactId;
        List<String> fields = new List<String>{ 'Id', relSchema.relatedContactField };
        if (String.isNotBlank(relSchema.roleField)) {
            fields.add(relSchema.roleField);
        }
        if (String.isNotBlank(relSchema.activeField)) {
            fields.add(relSchema.activeField);
        }

        String soql =
            'SELECT ' + String.join(fields, ', ') +
            ' FROM ' + relSchema.objectName +
            ' WHERE ' + relSchema.primaryContactField + ' = :primaryContactId';
        if (String.isNotBlank(relSchema.activeField)) {
            soql += ' AND ' + relSchema.activeField + ' = true';
        }
        soql += ' ORDER BY CreatedDate DESC';

        List<SObject> relations = Database.query(soql);
        Map<Id, Account> accountsByContactId =
            getPersonAccountsByContactId(relations, relSchema.relatedContactField);
        Map<Id, String> roleNamesById = getRoleNamesById(relations, relSchema);

        for (SObject rel : relations) {
            Id relatedContactId = (Id) rel.get(relSchema.relatedContactField);
            Account relatedAccount = accountsByContactId.get(relatedContactId);
            if (relatedAccount == null) {
                continue;
            }

            Map<String, Object> row = new Map<String, Object>();
            row.put('Id', rel.get('Id'));
            row.put('Role', getRoleValue(rel, relSchema, roleNamesById));
            row.put('Name', relatedAccount.Name);
            row.put('DOB', String.valueOf(relatedAccount.PersonBirthdate));
            row.put(
                'Phone',
                relatedAccount.PersonHomePhone != null
                    ? relatedAccount.PersonHomePhone
                    : relatedAccount.PersonMobilePhone
            );
            row.put(
                'Address',
                buildAddress(
                    relatedAccount.BillingStreet,
                    relatedAccount.BillingCity,
                    relatedAccount.BillingState,
                    relatedAccount.BillingPostalCode
                )
            );
            flatList.add(row);
        }

        return associationsResult(flatList);
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getHistory(Id minorAccountId) {
        Account minorAcc = [
            SELECT PersonContactId
            FROM Account
            WHERE Id = :minorAccountId
        ];

        List<Map<String, Object>> history = new List<Map<String, Object>>();
        RelationshipSchema relSchema = getRelationshipSchema();
        if (minorAcc.PersonContactId == null || !relSchema.hasContactFields()) {
            return history;
        }

        Id primaryContactId = minorAcc.PersonContactId;
        List<String> fields = new List<String>{
            'Id',
            relSchema.relatedContactField,
            'CreatedBy.Name',
            'CreatedDate',
            'LastModifiedBy.Name',
            'LastModifiedDate'
        };
        if (String.isNotBlank(relSchema.activeField)) {
            fields.add(relSchema.activeField);
        }
        if (String.isNotBlank(relSchema.endDateField)) {
            fields.add(relSchema.endDateField);
        }

        String soql =
            'SELECT ' + String.join(fields, ', ') +
            ' FROM ' + relSchema.objectName +
            ' WHERE ' + relSchema.primaryContactField + ' = :primaryContactId' +
            ' ORDER BY CreatedDate DESC';

        List<SObject> allRels = Database.query(soql);
        Map<Id, Account> accountsByContactId =
            getPersonAccountsByContactId(allRels, relSchema.relatedContactField);

        for (SObject rel : allRels) {
            Id relatedContactId = (Id) rel.get(relSchema.relatedContactField);
            Account relatedAccount = accountsByContactId.get(relatedContactId);
            String relatedName = relatedAccount == null ? null : relatedAccount.Name;

            Map<String, Object> addRow = new Map<String, Object>();
            addRow.put('Id', String.valueOf(rel.get('Id')) + '_add');
            addRow.put('Name', relatedName);
            addRow.put('ActionPerformed', 'Added');
            addRow.put('UserName', getParentName(rel, 'CreatedBy'));
            addRow.put('DateTime', rel.get('CreatedDate'));
            history.add(addRow);

            Boolean isActive = String.isNotBlank(relSchema.activeField)
                ? (Boolean) rel.get(relSchema.activeField)
                : true;
            Object endDateValue = String.isNotBlank(relSchema.endDateField)
                ? rel.get(relSchema.endDateField)
                : null;
            if (!isActive && endDateValue != null) {
                Map<String, Object> removeRow = new Map<String, Object>();
                removeRow.put('Id', String.valueOf(rel.get('Id')) + '_remove');
                removeRow.put('Name', relatedName);
                removeRow.put('ActionPerformed', 'Removed');
                removeRow.put('UserName', getParentName(rel, 'LastModifiedBy'));
                removeRow.put('DateTime', rel.get('LastModifiedDate'));
                history.add(removeRow);
            }
        }

        return history;
    }

    @AuraEnabled
    public static void addAssociation(
            Id minorAccountId,
            Id guardianAccountId,
            String role) {
        Account minorAcc = [
            SELECT PersonContactId
            FROM Account
            WHERE Id = :minorAccountId
        ];
        Account guardianAcc = [
            SELECT PersonContactId
            FROM Account
            WHERE Id = :guardianAccountId
        ];

        RelationshipSchema relSchema = getRelationshipSchema();
        if (!relSchema.hasContactFields()) {
            throw new AuraHandledException(
                'Contact relationship fields are not configured for '
                + RELATIONSHIP_OBJECT + '.'
            );
        }

        Id primaryContactId = minorAcc.PersonContactId;
        Id relatedContactId = guardianAcc.PersonContactId;
        String duplicateSoql =
            'SELECT Id FROM ' + relSchema.objectName +
            ' WHERE ' + relSchema.primaryContactField + ' = :primaryContactId' +
            ' AND ' + relSchema.relatedContactField + ' = :relatedContactId';
        if (String.isNotBlank(relSchema.activeField)) {
            duplicateSoql += ' AND ' + relSchema.activeField + ' = true';
        }
        duplicateSoql += ' LIMIT 1';

        if (!Database.query(duplicateSoql).isEmpty()) {
            throw new AuraHandledException(
                'This person is already an active Parent/Guardian for this record.'
            );
        }

        SObject relationshipRecord =
            Schema.getGlobalDescribe().get(relSchema.objectName).newSObject();
        relationshipRecord.put(relSchema.primaryContactField, primaryContactId);
        relationshipRecord.put(relSchema.relatedContactField, relatedContactId);
        if (String.isNotBlank(relSchema.accountField)) {
            relationshipRecord.put(relSchema.accountField, minorAccountId);
        }
        if (String.isNotBlank(relSchema.roleField)) {
            relationshipRecord.put(
                relSchema.roleField,
                resolveRoleValue(role, relSchema)
            );
        }
        if (String.isNotBlank(relSchema.activeField)) {
            relationshipRecord.put(relSchema.activeField, true);
        }
        insert relationshipRecord;
    }

    @AuraEnabled
    public static void removeAssociation(Id relationId) {
        RelationshipSchema relSchema = getRelationshipSchema();
        if (String.isBlank(relSchema.activeField)
                || String.isBlank(relSchema.endDateField)) {
            throw new AuraHandledException(
                'Contact relationship active/end date fields are not configured.'
            );
        }

        String soql =
            'SELECT Id, ' + relSchema.activeField + ', ' +
            relSchema.endDateField +
            ' FROM ' + relSchema.objectName +
            ' WHERE Id = :relationId';
        SObject rel = Database.query(soql);
        rel.put(relSchema.activeField, false);
        rel.put(relSchema.endDateField, Date.today());
        update rel;
    }

    @AuraEnabled
    public static void createAndAssociate(
            Id minorAccountId,
            String firstName,
            String lastName,
            Date dob,
            String phone,
            String street,
            String city,
            String state,
            String postalCode,
            String role) {
        Id personAccountRTId =
            Schema.SObjectType.Account
                .getRecordTypeInfosByDeveloperName()
                .get('PersonAccount')
                .getRecordTypeId();

        Account newPA = new Account(
            FirstName = firstName,
            LastName = lastName,
            PersonBirthdate = dob,
            PersonHomePhone = phone,
            BillingStreet = street,
            BillingCity = city,
            BillingState = state,
            BillingPostalCode = postalCode,
            RecordTypeId = personAccountRTId
        );
        insert newPA;

        addAssociation(minorAccountId, newPA.Id, role);
    }

    private static RelationshipSchema getRelationshipSchema() {
        RelationshipSchema relSchema = new RelationshipSchema();
        relSchema.objectName = RELATIONSHIP_OBJECT;

        Schema.SObjectType relationshipType =
            Schema.getGlobalDescribe().get(RELATIONSHIP_OBJECT);
        if (relationshipType == null) {
            return relSchema;
        }

        Map<String, Schema.SObjectField> fields =
            relationshipType.getDescribe().fields.getMap();
        relSchema.primaryContactField = firstExistingField(
            fields,
            new List<String>{
                'Primary_Contact__c',
                'Contact__c',
                'PrimaryContact__c',
                'HealthCloudGA__Contact__c'
            }
        );
        relSchema.relatedContactField = firstExistingField(
            fields,
            new List<String>{
                'Related_Contact__c',
                'RelatedContact__c',
                'Guardian_Contact__c',
                'HealthCloudGA__RelatedContact__c'
            }
        );
        relSchema.accountField = firstExistingField(
            fields,
            new List<String>{ 'Account__c', 'Patient__c', 'Minor_Account__c' }
        );
        relSchema.roleField = firstExistingField(
            fields,
            new List<String>{
                'Relationship_Type__c',
                'RelationshipType__c',
                'Role__c',
                'HealthCloudGA__Role__c'
            }
        );
        relSchema.activeField = firstExistingField(
            fields,
            new List<String>{
                'Is_Active__c',
                'Active__c',
                'HealthCloudGA__Active__c'
            }
        );
        relSchema.endDateField = firstExistingField(
            fields,
            new List<String>{
                'End_Date__c',
                'EndDate__c',
                'HealthCloudGA__EndDate__c'
            }
        );
        return relSchema;
    }

    private static String firstExistingField(
            Map<String, Schema.SObjectField> fields,
            List<String> candidateNames) {
        for (String candidateName : candidateNames) {
            if (fields.containsKey(candidateName)) {
                return candidateName;
            }
        }
        return null;
    }

    private static Map<String, Object> associationsResult(
            List<Map<String, Object>> rows) {
        Map<String, Object> result = new Map<String, Object>();
        result.put('associations', rows);
        result.put('totalCount', rows.size());
        return result;
    }

    private static Map<Id, Account> getPersonAccountsByContactId(
            List<SObject> relationships,
            String relatedContactField) {
        Set<Id> contactIds = new Set<Id>();
        for (SObject relationshipRecord : relationships) {
            Id relatedContactId = (Id) relationshipRecord.get(relatedContactField);
            if (relatedContactId != null) {
                contactIds.add(relatedContactId);
            }
        }

        Map<Id, Id> accountIdsByContactId = new Map<Id, Id>();
        Set<Id> accountIds = new Set<Id>();
        for (Contact contactRecord : [
            SELECT Id, AccountId
            FROM Contact
            WHERE Id IN :contactIds
        ]) {
            if (contactRecord.AccountId != null) {
                accountIdsByContactId.put(contactRecord.Id, contactRecord.AccountId);
                accountIds.add(contactRecord.AccountId);
            }
        }

        Map<Id, Account> accountsById = new Map<Id, Account>([
            SELECT Id,
                   Name,
                   PersonBirthdate,
                   BillingStreet,
                   BillingCity,
                   BillingState,
                   BillingPostalCode,
                   PersonHomePhone,
                   PersonMobilePhone
            FROM Account
            WHERE Id IN :accountIds
        ]);

        Map<Id, Account> accountsByContactId = new Map<Id, Account>();
        for (Id contactId : accountIdsByContactId.keySet()) {
            accountsByContactId.put(
                contactId,
                accountsById.get(accountIdsByContactId.get(contactId))
            );
        }
        return accountsByContactId;
    }

    private static Object resolveRoleValue(String role, RelationshipSchema relSchema) {
        if (String.isBlank(role) || String.isBlank(relSchema.roleField)) {
            return null;
        }

        Schema.DescribeFieldResult roleDescribe =
            Schema.getGlobalDescribe()
                .get(relSchema.objectName)
                .getDescribe()
                .fields
                .getMap()
                .get(relSchema.roleField)
                .getDescribe();
        if (roleDescribe.getType() != Schema.DisplayType.Reference) {
            return role;
        }

        try {
            return (Id) role;
        } catch (Exception ignored) {
            // The UI may pass a role name when the relationship object stores a role lookup.
        }

        for (Schema.SObjectType referenceType : roleDescribe.getReferenceTo()) {
            String referenceObjectName = referenceType.getDescribe().getName();
            if (!referenceType.getDescribe().fields.getMap().containsKey('Name')) {
                continue;
            }

            List<SObject> roleMatches = Database.query(
                'SELECT Id FROM ' + referenceObjectName +
                ' WHERE Name = :role LIMIT 1'
            );
            if (!roleMatches.isEmpty()) {
                return roleMatches[0].get('Id');
            }
        }

        throw new AuraHandledException('Unable to find relationship role: ' + role);
    }

    private static Map<Id, String> getRoleNamesById(
            List<SObject> relationships,
            RelationshipSchema relSchema) {
        Map<Id, String> roleNamesById = new Map<Id, String>();
        if (String.isBlank(relSchema.roleField)) {
            return roleNamesById;
        }

        Schema.DescribeFieldResult roleDescribe =
            Schema.getGlobalDescribe()
                .get(relSchema.objectName)
                .getDescribe()
                .fields
                .getMap()
                .get(relSchema.roleField)
                .getDescribe();
        if (roleDescribe.getType() != Schema.DisplayType.Reference
                || roleDescribe.getReferenceTo().isEmpty()) {
            return roleNamesById;
        }

        Set<Id> roleIds = new Set<Id>();
        for (SObject relationshipRecord : relationships) {
            Object roleValue = relationshipRecord.get(relSchema.roleField);
            if (roleValue != null) {
                roleIds.add((Id) roleValue);
            }
        }
        if (roleIds.isEmpty()) {
            return roleNamesById;
        }

        String referenceObjectName =
            roleDescribe.getReferenceTo()[0].getDescribe().getName();
        if (!roleDescribe.getReferenceTo()[0]
                .getDescribe()
                .fields
                .getMap()
                .containsKey('Name')) {
            return roleNamesById;
        }

        for (SObject roleRecord : Database.query(
                'SELECT Id, Name FROM ' + referenceObjectName +
                ' WHERE Id IN :roleIds')) {
            roleNamesById.put((Id) roleRecord.get('Id'), (String) roleRecord.get('Name'));
        }
        return roleNamesById;
    }

    private static Object getRoleValue(
            SObject relationshipRecord,
            RelationshipSchema relSchema,
            Map<Id, String> roleNamesById) {
        if (String.isBlank(relSchema.roleField)) {
            return null;
        }

        Object roleValue = relationshipRecord.get(relSchema.roleField);
        if (!roleNamesById.isEmpty() && roleValue != null) {
            Id roleId = (Id) roleValue;
            if (roleNamesById.containsKey(roleId)) {
                return roleNamesById.get(roleId);
            }
        }
        return roleValue;
    }

    private static String getParentName(SObject record, String relationshipName) {
        SObject parentRecord = record.getSObject(relationshipName);
        return parentRecord == null ? null : (String) parentRecord.get('Name');
    }

    private static String buildAddress(
            String street,
            String city,
            String state,
            String postal) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(street)) {
            parts.add(street);
        }
        if (String.isNotBlank(city)) {
            parts.add(city);
        }
        if (String.isNotBlank(state)) {
            parts.add(state);
        }
        if (String.isNotBlank(postal)) {
            parts.add(postal);
        }
        return String.join(parts, ', ');
    }
}
