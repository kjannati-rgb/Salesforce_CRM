// Phase B1/B4 smoke: single-record end-to-end through the orchestrator + stamp flow
List<Application_Settings__c> settings = [SELECT SetupOwnerId, Disable_Autolaunch_Lightning_Flow__c FROM Application_Settings__c];
System.debug('APP SETTINGS: ' + settings);

Task t = new Task(Subject = 'PFC: Cockpit B1 Smoke', Status = 'Completed', Priority = 'Normal', ActivityDate = Date.today());
insert t;

List<Pardot_Form_Completion__c> pfcs = [
    SELECT Id, Name, Form_Name__c, OwnerId, Owner.Name, Sales_Rep__c, PFC_Source__c,
           Sales_Stage__c, Clay_Routed__c, Routing_Overdue__c, Date_Completed__c, RecordType.DeveloperName
    FROM Pardot_Form_Completion__c
    WHERE Form_Name__c = 'Cockpit B1 Smoke'
    ORDER BY CreatedDate DESC LIMIT 1
];
System.assertEquals(1, pfcs.size(), 'ORCHESTRATOR DID NOT CREATE A PFC');
Pardot_Form_Completion__c p = pfcs[0];
System.debug('CREATED: owner=' + p.Owner.Name + ' rep=' + p.Sales_Rep__c + ' source=' + p.PFC_Source__c + ' rt=' + p.RecordType.DeveloperName);
System.assert(String.valueOf(p.OwnerId).startsWith('00G'), 'B1 FAIL: owner is not a queue: ' + p.OwnerId);
System.assertEquals('PFC Triage Queue', p.Owner.Name, 'B1 FAIL: wrong queue');
System.assertEquals(null, p.Sales_Rep__c, 'B1 FAIL: Sales_Rep should be blank at create');
System.assertEquals(false, p.Clay_Routed__c, 'Clay flag must start false');

// B4: disqualify -> Date_Completed stamped by the flow (WFRs are now inactive)
List<Schema.PicklistEntry> reasons = Pardot_Form_Completion__c.Reason_Disqualified__c.getDescribe().getPicklistValues();
p.Sales_Stage__c = 'Disqualified';
p.Reason_Disqualified__c = reasons[0].getValue();
update p;
p = [SELECT Id, Date_Completed__c, Sales_Stage__c FROM Pardot_Form_Completion__c WHERE Id = :p.Id];
System.assertNotEquals(null, p.Date_Completed__c, 'B4 FAIL: Date_Completed not stamped on disqualify');
DateTime firstStamp = p.Date_Completed__c;
System.debug('B4 stamp: ' + firstStamp);

// B4: reopen -> stamp must SURVIVE (new stamp-once semantics; old WFR would have nulled it)
p.Sales_Stage__c = 'Working';
update p;
p = [SELECT Id, Date_Completed__c FROM Pardot_Form_Completion__c WHERE Id = :p.Id];
System.assertEquals(firstStamp, p.Date_Completed__c, 'B4 FAIL: stamp lost on reopen');

// B4: re-close -> must NOT overwrite the original stamp
p.Sales_Stage__c = 'Disqualified';
update p;
p = [SELECT Id, Date_Completed__c FROM Pardot_Form_Completion__c WHERE Id = :p.Id];
System.assertEquals(firstStamp, p.Date_Completed__c, 'B4 FAIL: stamp overwritten on re-close');

// B1: flag record overdue while queue-owned, then simulate the Clay response (B2 round trip)
p.Sales_Stage__c = 'Working';   // unlock from Disqualified for rep-context realism (admin bypasses the lock VR anyway)
p.Routing_Overdue__c = true;
update p;
p = [SELECT Id, Routing_Overdue__c, OwnerId FROM Pardot_Form_Completion__c WHERE Id = :p.Id];
System.assert(p.Routing_Overdue__c, 'flag should persist while queue-owned');

User rep = [SELECT Id, Name FROM User WHERE IsActive = true AND Profile.Name = 'Custom: Sales Profile' LIMIT 1];
p.OwnerId = rep.Id;
p.Sales_Rep__c = rep.Id;
p.Fit_Score__c = 87;
p.Score_Reasoning__c = 'Simulated Clay response: strong ICP match (smoke test).';
p.Clay_Routed__c = true;
update p;
p = [SELECT Id, Routing_Overdue__c, Sales_Rep__r.Name, Fit_Score__c, Clay_Routed__c, Owner.Name FROM Pardot_Form_Completion__c WHERE Id = :p.Id];
System.assertEquals(false, p.Routing_Overdue__c, 'B1 FAIL: overdue flag not cleared when user took ownership');
System.assertEquals(87, p.Fit_Score__c, 'B2 FAIL: fit score did not land');
System.assert(p.Clay_Routed__c, 'B2 FAIL: response stamp did not land');
System.debug('ROUND TRIP OK: owner=' + p.Owner.Name + ' rep=' + p.Sales_Rep__r.Name + ' score=' + p.Fit_Score__c);

// cleanup
delete [SELECT Id FROM Pardot_Form_Completion__c WHERE Id = :p.Id];
delete t;
System.debug('B1_SMOKE_PASS');
