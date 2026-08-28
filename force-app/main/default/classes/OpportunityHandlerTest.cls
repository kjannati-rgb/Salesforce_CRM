@isTest
public class OpportunityHandlerTest {

    @isTest
    public static void test1(){
        
        Application_Settings__c orgSetting = new Application_Settings__c();
        orgSetting.SetupOwnerId = UserInfo.getOrganizationId(); 
        orgSetting.Disable_Autolaunch_Lightning_Flow__c = True;
        insert orgSetting;
        
        Account Ultimateacc =new Account();
        Ultimateacc.RecordTypeId='0126g000000OhUSAA0';
        Ultimateacc.Name='abc';
        //acc.Ultimate_Account__c=;
        Ultimateacc.BillingCity='Tirana';
        Ultimateacc.BillingCountry='Albania';
        insert Ultimateacc;
        Account acc =new Account();
        acc.Name='abc';
        acc.Ultimate_Account__c=Ultimateacc.Id;
        acc.BillingCity='Tirana';
        acc.BillingCountry='Albania';
        insert acc;
        
        Contact pc =new Contact();
        //pc.name='pc';
        pc.LastName='av';
        
        pc.AccountId=acc.id;
        insert pc;
        
        Opportunity OppNew =new Opportunity();
        OppNew.Name='Schedule test1';
        OppNew.StageName='Identify';
        OppNew.Probability=10;
        OppNew.LeadSource='Form Completion';
        OppNew.CloseDate=system.today();
        Test.startTest();
        INSERT OppNew;
        
     Opportunity OppOld =new Opportunity();
        OppOld.Name='Schedule test1';
        OppOld.StageName='Closed Won';
        OppOld.Probability=10;
        OppOld.LeadSource='Form Completion';
        OppOld.CloseDate=system.today();
        OppOld.Ultimate_Account__c=acc.Id;
        OppOld.AccountId=acc.Id;
        
        INSERT OppOld;
        Test.stopTest();
        SBQQ__Quote__c q=new SBQQ__Quote__c();
        q.ApprovalStatus__c='Approved';
        q.Approved__c=true;
        q.SBQQ__Opportunity2__c=OppNew.id;
        q.SBQQ__Status__c='Approved';
        q.SBQQ__Primary__c=True;
        q.SBQQ__PrimaryContact__c=pc.id;
        insert q;
        OppNew.StageName='Closed Won – Pending Approval';
        List<Opportunity> NewOppRecords=new List<Opportunity>();
     NewOppRecords.add(OppNew);
     Map<id,Opportunity> OldOppRecords =new Map<id,Opportunity>();
        
     OldOppRecords.put(OppNew.id,OppOld);
        
        //Map<id,Opportunity> OldOppRecords2 =new Map<id,Opportunity>();
       //Opportunity OppOld1 =new Opportunity();
     //Map<id,Opportunity> OldOppRecordsNull =new Map<id,Opportunity>();  
        //OldOppRecordsNull.put(OppNew.id,OppOld1);
        OpportunityHandler.LockOppRecords(NewOppRecords,OldOppRecords);
        //OpportunityHandler.LockOppRecords(NewOppRecords,OldOppRecordsNull);
        
    }
    
    
  @isTest
    public static void test2(){
        
        Application_Settings__c orgSetting = new Application_Settings__c();
        orgSetting.SetupOwnerId = UserInfo.getOrganizationId(); 
        orgSetting.Disable_Autolaunch_Lightning_Flow__c = True;
        insert orgSetting;
        
        Account Ultimateacc =new Account();
        Ultimateacc.RecordTypeId='0126g000000OhUSAA0';
        Ultimateacc.Name='abc';
        //acc.Ultimate_Account__c=;
        Ultimateacc.BillingCity='Tirana';
        Ultimateacc.BillingCountry='Albania';
        insert Ultimateacc;
        Account acc =new Account();
        acc.Name='abc';
        acc.Ultimate_Account__c=Ultimateacc.Id;
        acc.BillingCity='Tirana';
        acc.BillingCountry='Albania';
        insert acc;
        
        Contact pc =new Contact();
        //pc.name='pc';
        pc.LastName='av';
        
        pc.AccountId=acc.id;
        insert pc;
        
        Opportunity OppNew =new Opportunity();
        OppNew.Name='Schedule test1';
        OppNew.StageName='Identify';
        OppNew.Probability=10;
        OppNew.LeadSource='Form Completion';
        OppNew.CloseDate=system.today();
        Test.startTest();
        INSERT OppNew;
    Opportunity OppOld =new Opportunity();
        OppOld.Name='Schedule test1';
        OppOld.StageName='Closed Won';
        OppOld.Probability=10;
        OppOld.LeadSource='Form Completion';
        OppOld.CloseDate=system.today();
        OppOld.Ultimate_Account__c=acc.Id;
        OppOld.AccountId=acc.Id;
        INSERT OppOld;
        Test.stopTest();
        SBQQ__Quote__c q=new SBQQ__Quote__c();
        q.ApprovalStatus__c='Approved';
        q.Approved__c=true;
        q.SBQQ__Opportunity2__c=OppNew.id;
        q.SBQQ__Status__c='Approved';
        q.SBQQ__Primary__c=True;
        q.SBQQ__PrimaryContact__c=pc.id;
        insert q;
        OppNew.StageName='Closed Won – Pending Approval';
        List<Opportunity> NewOppRecords=new List<Opportunity>();
     NewOppRecords.add(OppNew);
     Map<id,Opportunity> OldOppRecords =new Map<id,Opportunity>();
        
     OldOppRecords.put(OppNew.id,null);
        
        //Map<id,Opportunity> OldOppRecords2 =new Map<id,Opportunity>();
       
        OpportunityHandler.LockOppRecords(NewOppRecords,null);


    }

    // ---- Lock-gating test matrix (open->closed, closed->open, closed->closed edit,
    // ---- closed insert, bulk 200) for the bulk/boundary-gated Approval.isLocked path ----

    private static Opportunity buildOpp(String name, String stage) {
        return new Opportunity(
            Name = name,
            StageName = stage,
            Probability = 10,
            LeadSource = 'Form Completion',
            CloseDate = System.today()
        );
    }

    private static void bypassFlows() {
        Application_Settings__c orgSetting = new Application_Settings__c();
        orgSetting.SetupOwnerId = UserInfo.getOrganizationId();
        orgSetting.Disable_Autolaunch_Lightning_Flow__c = true;
        insert orgSetting;
    }

    @isTest
    public static void testOpenToClosedLocks() {
        bypassFlows();
        Opportunity opp = buildOpp('Matrix open to closed', 'Identify');
        insert opp;
        System.assertEquals(false, Approval.isLocked(opp.Id), 'Open-stage opp must start unlocked');

        Opportunity oldSnapshot = buildOpp('Matrix open to closed', 'Identify');
        oldSnapshot.Id = opp.Id;
        opp.StageName = 'Closed Won';

        Test.startTest();
        OpportunityHandler.processedLockIds.clear();
        OpportunityHandler.LockOppRecords(
            new List<Opportunity>{ opp },
            new Map<Id, Opportunity>{ opp.Id => oldSnapshot }
        );
        Test.stopTest();

        System.assertEquals(true, Approval.isLocked(opp.Id), 'Crossing open->closed must lock the record');
    }

    @isTest
    public static void testClosedToOpenUnlocks() {
        bypassFlows();
        Opportunity opp = buildOpp('Matrix closed to open', 'Identify');
        insert opp;
        Approval.lock(opp.Id);
        System.assertEquals(true, Approval.isLocked(opp.Id), 'Precondition: record locked');

        Opportunity oldSnapshot = buildOpp('Matrix closed to open', 'Closed Won');
        oldSnapshot.Id = opp.Id;
        opp.StageName = 'Identify';

        Test.startTest();
        OpportunityHandler.processedLockIds.clear();
        OpportunityHandler.LockOppRecords(
            new List<Opportunity>{ opp },
            new Map<Id, Opportunity>{ opp.Id => oldSnapshot }
        );
        Test.stopTest();

        System.assertEquals(false, Approval.isLocked(opp.Id), 'Crossing closed->open must unlock the record');
    }

    @isTest
    public static void testClosedToClosedEditSkipsLockWork() {
        bypassFlows();
        Opportunity opp = buildOpp('Matrix closed to closed', 'Identify');
        insert opp;

        Opportunity oldSnapshot = buildOpp('Matrix closed to closed', 'Closed Won');
        oldSnapshot.Id = opp.Id;
        opp.StageName = 'Closed Lost';

        Test.startTest();
        OpportunityHandler.processedLockIds.clear();
        Integer queriesBefore = Limits.getQueries();
        OpportunityHandler.LockOppRecords(
            new List<Opportunity>{ opp },
            new Map<Id, Opportunity>{ opp.Id => oldSnapshot }
        );
        Integer queriesUsed = Limits.getQueries() - queriesBefore;
        Test.stopTest();

        // Stage stayed inside the closed set: no boundary crossing, so no lock API call
        System.assertEquals(0, queriesUsed, 'Closed->closed edit must not consume any queries');
        System.assertEquals(false, Approval.isLocked(opp.Id), 'Closed->closed edit performs no lock work');
    }

    @isTest
    public static void testClosedInsertLocks() {
        bypassFlows();
        Account ultimateAcc = new Account(
            RecordTypeId = '0126g000000OhUSAA0',
            Name = 'Matrix Ultimate',
            BillingCity = 'Tirana',
            BillingCountry = 'Albania'
        );
        insert ultimateAcc;
        Account acc = new Account(
            Name = 'Matrix Office',
            Ultimate_Account__c = ultimateAcc.Id,
            BillingCity = 'Tirana',
            BillingCountry = 'Albania'
        );
        insert acc;

        Opportunity opp = buildOpp('Matrix closed insert', 'Closed Won');
        opp.AccountId = acc.Id;
        opp.Ultimate_Account__c = acc.Id;
        Test.startTest();
        insert opp; // real trigger path: after insert, oldMap null
        Test.stopTest();

        System.assertEquals(true, Approval.isLocked(opp.Id), 'Record inserted directly in a closed stage must lock');
    }

    @isTest
    public static void testBulk200SingleLockQuery() {
        bypassFlows();
        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < 200; i++) {
            opps.add(buildOpp('Matrix bulk ' + i, 'Identify'));
        }
        insert opps;

        Map<Id, Opportunity> oldMap = new Map<Id, Opportunity>();
        for (Opportunity opp : opps) {
            Opportunity oldSnapshot = buildOpp(opp.Name, 'Identify');
            oldSnapshot.Id = opp.Id;
            oldMap.put(opp.Id, oldSnapshot);
            opp.StageName = 'Closed Won';
        }

        Test.startTest();
        OpportunityHandler.processedLockIds.clear();
        Integer queriesBefore = Limits.getQueries();
        OpportunityHandler.LockOppRecords(opps, oldMap);
        Integer queriesUsed = Limits.getQueries() - queriesBefore;
        Test.stopTest();

        System.assert(queriesUsed <= 2,
            'Bulk 200 must use one bulk isLocked call, not one per record. Used: ' + queriesUsed);

        Map<Id, Boolean> lockedById = Approval.isLocked(new List<Id>(oldMap.keySet()));
        for (Id oppId : lockedById.keySet()) {
            System.assertEquals(true, lockedById.get(oppId), 'All 200 records must be locked');
        }

        // Repeat save in the same transaction: processed-id set makes it free
        Integer repeatBefore = Limits.getQueries();
        OpportunityHandler.LockOppRecords(opps, oldMap);
        System.assertEquals(0, Limits.getQueries() - repeatBefore,
            'A repeated save of already-processed records must not consume queries');
    }

}