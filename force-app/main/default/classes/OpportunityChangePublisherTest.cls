@IsTest
private class OpportunityChangePublisherTest {
    
    @TestSetup
    static void setupData() {
        TestDataFactory.bypassAutomation();
        // User to own the Opportunities (ensures Owner fields are populated)
        User u = [SELECT Id FROM User WHERE IsActive = true AND Profile.Name = 'System Administrator' LIMIT 1];
        
        Account Ultacc1 = new Account();
        Ultacc1.Name = 'Account With Firm1';
        Ultacc1.RecordTypeId='0126g000000OhUSAA0';
        insert Ultacc1;
        
        Account office1 = new Account();
        office1.Name = 'Account Without Firm1';
        office1.RecordTypeId='0126g000000OhUTAA0';
        office1.Ultimate_Account__c=Ultacc1.Id;
        office1.BillingCity='Tirana';
        office1.BillingCountry='Albania';
        office1.MBL_Seminars_FirmID__c = '123';
        insert office1;
        
        Contact pc1 =new Contact();
        //pc.name='pc';
        pc1.LastName='av';
        
        pc1.AccountId=office1.id;
        insert pc1;
        
        Account Ultacc2 = new Account();
        Ultacc2.Name = 'Account With Firm2';
        Ultacc2.RecordTypeId='0126g000000OhUSAA0';
        insert Ultacc2;
        
        Account office2 = new Account();
        office2.Name = 'Account Without Firm2';
        office2.Ultimate_Account__c=Ultacc1.Id;
        office2.RecordTypeId='0126g000000OhUTAA0';
        office2.BillingCity='Tirana';
        office2.BillingCountry='Albania';
        office2.MBL_Seminars_FirmID__c = '';
        insert office2;
        
        Contact pc2 =new Contact();
        //pc.name='pc';
        pc2.LastName='av';
        pc2.AccountId=office2.id;
        insert pc2;
        
        // Opportunity that should publish (has Account with mbl Firm ID)
        Opportunity oppPublishInsert = new Opportunity(
            Name = 'Opp Insert Publish',
            StageName = 'Identify',
            CloseDate = Date.today().addDays(30),
            AccountId = office1.Id,
            OwnerId = u.Id,
            Amount = 1000
        );
        insert oppPublishInsert;
        
        // Opportunity that should NOT publish (no mbl Firm ID)
        Opportunity oppNoPublishInsert = new Opportunity(
            Name = 'Opp Insert No Publish',
            StageName = 'Identify',
            CloseDate = Date.today().addDays(30),
            AccountId = office2.Id,
            OwnerId = u.Id,
            Amount = 2000
        );
        insert oppNoPublishInsert;
        
        // Opportunity for update scenario (has mbl Firm ID)
        Opportunity oppPublishUpdate = new Opportunity(
            Name = 'Opp Update Publish',
            StageName = 'Identify',
            CloseDate = Date.today().addDays(30),
            AccountId = office1.Id,
            OwnerId = u.Id,
            Amount = 3000
        );
        insert oppPublishUpdate;
    }
    
    @IsTest
    static void testInsertPublishesForFirmIdAccounts() {
        // Retrieve Opportunities created in @TestSetup
        List<Opportunity> opps = [
            SELECT Id, AccountId
            FROM Opportunity
            WHERE Name IN ('Opp Insert Publish', 'Opp Insert No Publish')
        ];
        
        Test.startTest();
        Integer successCount = OpportunityChangePublisher.publishFor(
            opps,
            null,
            true,   // isInsert
            false   // isUpdate
        );
        Test.stopTest();
        
        // Only one of the Opps has an Account with Firm ID, so expect at least one success
        System.assertEquals(1, successCount,
                            'Exactly one event should have been published for insert with FirmID.');
    }
    /*
    @IsTest
    static void testUpdatePublishesOnlyForFirmIdAccounts() {
        // Query the update Opportunity (has Account with FirmID)
        Opportunity oppUpdate = [
            SELECT Id, AccountId, StageName, Amount
            FROM Opportunity
            WHERE Name = 'Opp Update Publish'
            LIMIT 1
        ];
        
        // Build oldMap BEFORE the update
        Map<Id, Opportunity> oldMap = new Map<Id, Opportunity>{ oppUpdate.Id => oppUpdate };
            
            // Simulate an update by changing fields and doing real DML
            oppUpdate.StageName = 'Identify';
        oppUpdate.Amount = 100;
        update oppUpdate;
       
        Test.startTest();
        Integer successCount = OpportunityChangePublisher.publishFor(
            new List<Opportunity>{ oppUpdate }, // this now has a valid Id
            oldMap,
            false,  // isInsert
            true    // isUpdate
        );
        Test.stopTest();
       
        System.assertEquals(1, successCount,
                            'Exactly one event should have been published for update with FirmID.');
 
    }
*/
    
    /*
    @IsTest
    static void testNoPublishWhenNoFirmIdOrNoAccount() {
        // Opportunity without Firm ID account
        Opportunity oppNoFirm = [
            SELECT Id, AccountId
            FROM Opportunity
            WHERE Name = 'Opp Insert No Publish'
            LIMIT 1
        ];
        
        // New Opportunity without any Account
        
        Opportunity oppNoAccount = new Opportunity(
            Name = 'Opp No Account',
            StageName = 'Identify',
            CloseDate = Date.today().addDays(30)
        );
        insert oppNoAccount;
        
        List<Opportunity> testOpps = new List<Opportunity>{ oppNoFirm, oppNoAccount };
            
            Test.startTest();
        Integer successCount = OpportunityChangePublisher.publishFor(
            testOpps,
            null,
            true,
            false
        );
        Test.stopTest();
        
        System.assertEquals(0, successCount,
                            'No events should be published when Account has no FirmID or Account is null.'); 
    }
*/
    /*
    @IsTest
    static void testNoEventsWhenInputEmptyOrNull() {
        Test.startTest();
        Integer fromNull = OpportunityChangePublisher.publishFor(
            null,
            null,
            true,
            false
        );
        Integer fromEmpty = OpportunityChangePublisher.publishFor(
            new List<Opportunity>(),
            null,
            false,
            true
        );
        Test.stopTest();
        
        System.assertEquals(0, fromNull, 'Null list should return 0.');
        System.assertEquals(0, fromEmpty, 'Empty list should return 0.');
    }
*/
}
