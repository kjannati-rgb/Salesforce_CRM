// PROD cutover smoke test: inbound PFC: task -> orchestrator creates Form Completion PFC. Cleans up after.
List<String> r = new List<String>();
Lead l = new Lead(FirstName='REV57', LastName='Cutover Smoke Test', Company='REV57 Smoke Test Co');
insert l;
Task t = new Task(Subject='PFC: REV57 Cutover Smoke Test Form', WhoId=l.Id, Status='Completed', Priority='Normal');
insert t;
List<Pardot_Form_Completion__c> p = [SELECT Id, RecordType.DeveloperName, Form_Name__c, Lead__c, Sales_Stage__c, Sales_Rep__c
    FROM Pardot_Form_Completion__c WHERE Lead__c = :l.Id];
r.add('count=' + p.size());
for (Pardot_Form_Completion__c x : p) {
    r.add('rt=' + x.RecordType.DeveloperName + ' form=[' + x.Form_Name__c + '] lead=' + x.Lead__c + ' stage=' + x.Sales_Stage__c + ' rep=' + x.Sales_Rep__c);
}
Boolean ok = p.size()==1 && p[0].RecordType.DeveloperName=='Form_Completion' && p[0].Lead__c==l.Id && p[0].Sales_Stage__c=='New';
r.add('RESULT=' + (ok ? 'PASS' : 'FAIL'));
// cleanup
try { if(!p.isEmpty()) delete p; } catch(Exception e){ r.add('cleanup pfc: '+e.getMessage()); }
try { delete t; } catch(Exception e){ r.add('cleanup task: '+e.getMessage()); }
try { delete l; } catch(Exception e){ r.add('cleanup lead: '+e.getMessage()); }
r.add('cleaned up');
for (String s : r) System.debug('PRODSMOKE ' + s);
