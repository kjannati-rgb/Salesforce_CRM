@isTest
public class UpdateAllFirmAccountClientStatusTest {

    @TestSetup
    static void bypassSetupAuto() {
        TestDataFactory.bypassAutomation();
    }

    
    @isTest
    static void testBatchExecution_ActiveStatus() {
        
        String firmRecordTypeID = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Firm').getRecordTypeId();
        String officeRecordTypeID = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Office').getRecordTypeId();
        
        // Create Test Account
        Account acc = new Account(
            Name = 'Test Firm Account',
            RecordTypeId = firmRecordTypeID,
            Client_Status__c = 'No'
        );
        insert acc;
        
        Account officeAcc = new Account(
            Name = 'Test Office Account',
            RecordTypeId = officeRecordTypeID,
            Ultimate_Account__c = acc.Id
        );
        insert officeAcc;
        
        // Create Opportunities
        
        // 1. Open Opportunity (should make status Active)
        Opportunity opp1 = new Opportunity(
            Name = 'Open Opp',
            AccountId = officeAcc.Id,
            Ultimate_Account__c = acc.Id,
            StageName = 'Qualify',
            CloseDate = Date.today().addDays(10),
            Type = 'Renewal'
        );
        
        // 2. Closed Won Opportunity
        Opportunity opp2 = new Opportunity(
            Name = 'Closed Won Opp',
            AccountId = officeAcc.Id,
            Ultimate_Account__c = acc.Id,
            StageName = 'Closed Won',
            CloseDate = Date.today(),
            Type = 'Upsell'
        );
        
        insert new List<Opportunity>{opp1, opp2};
            
            ///////////
            
            Test.startTest();
        
        UpdateAllFirmAccountClientStatusBatch batch = new UpdateAllFirmAccountClientStatusBatch();
        Database.executeBatch(batch, 1);
        /*
        String cronExp = '0 0 0 1 1 ? 2099'; // Future date
        System.schedule(
            'Test Batch Scheduler',
            cronExp,
            new UpdateAllFirmAccountClientStatusBatchSch()
        );*/
        
        Test.stopTest();
        
        // Verify result
        Account acc1 = [SELECT Client_Status__c FROM Account WHERE RecordType.Name = 'Firm' LIMIT 1];
        System.assertEquals('Active', acc1.Client_Status__c, 'Account should be Active');
    }
    
    @isTest
    static void testBatchExecution_ChurnedStatus() {
        
        String firmRecordTypeID = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Firm').getRecordTypeId();
        String officeRecordTypeID = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Office').getRecordTypeId();
        
        Account acc = new Account(
            Name = 'Churned Account',
            RecordTypeId = firmRecordTypeID,
            Client_Status__c = 'No'
        );
        insert acc;
        
        Account officeAcc = new Account(
            Name = 'Test Office Account',
            RecordTypeId = officeRecordTypeID,
            Ultimate_Account__c = acc.Id
        );
        insert officeAcc;
        
        // Only Closed Won Opportunity (no open opp)
        Opportunity opp = new Opportunity(
            Name = 'Closed Won Only',
            AccountId = officeAcc.Id,
            Ultimate_Account__c = acc.Id,
            StageName = 'Closed Won',
            CloseDate = Date.today(),
            Type = 'Upsell'
        );
        insert opp;
        
        Test.startTest();
        
        UpdateAllFirmAccountClientStatusBatch batch = new UpdateAllFirmAccountClientStatusBatch();
        Database.executeBatch(batch, 1);
        
        Test.stopTest();
        
        Account updatedAcc = [SELECT Client_Status__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('Churned', updatedAcc.Client_Status__c, 'Account should be Churned');
    }
    
    @isTest
    static void testBatchExecution_NoStatus() {
        
        String firmRecordTypeID = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Firm').getRecordTypeId();
        
        Account acc = new Account(
            Name = 'No Opp Account',
            RecordTypeId = firmRecordTypeID,
            Client_Status__c = 'Active'
        );
        insert acc;
        
        Test.startTest();
        
        UpdateAllFirmAccountClientStatusBatch batch = new UpdateAllFirmAccountClientStatusBatch();
        Database.executeBatch(batch, 1);
        
        Test.stopTest();
        
        Account updatedAcc = [SELECT Client_Status__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('No', updatedAcc.Client_Status__c, 'Account should be No');
    }
    
}