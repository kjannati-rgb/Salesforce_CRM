List<String> r = new List<String>();
Account acct = new Account(Name='REV57 Phase4 Acct'); insert acct;

// #9 non-matching prefix -> no PFC (entry gate excludes it)
try {
    Contact c = new Contact(LastName='REV57_P4_NoPrefix', AccountId=acct.Id); insert c;
    insert new Task(Subject='Just a normal task with no prefix', WhoId=c.Id, Status='Completed', Priority='Normal');
    Integer n = [SELECT COUNT() FROM Pardot_Form_Completion__c WHERE Contact__c = :c.Id];
    r.add('#9 non-matching prefix (expect 0): ' + (n==0 ? 'PASS' : 'FAIL n='+n));
} catch(Exception e){ r.add('#9 ERROR '+e.getMessage()); }

// #6 hyphenated name -> 1 NF PFC, Form_Name null (proves no subject identity parsing)
try {
    Contact c = new Contact(LastName='REV57_P4_Hyphen', AccountId=acct.Id); insert c;
    insert new Task(Subject='NF - Anna-Marie O\'Brien - Lexology - Free Newsfeed Subscriber - June 2026', WhoId=c.Id, Status='Completed', Priority='Normal');
    List<Pardot_Form_Completion__c> p = [SELECT RecordType.DeveloperName, Form_Name__c FROM Pardot_Form_Completion__c WHERE Contact__c = :c.Id];
    Boolean ok = p.size()==1 && p[0].RecordType.DeveloperName=='Newsfeed_Subscribers' && (p[0].Form_Name__c==null || p[0].Form_Name__c=='');
    r.add('#6 hyphenated/apostrophe name (1 NF PFC, no parse): ' + (ok ? 'PASS' : 'FAIL size='+p.size()));
} catch(Exception e){ r.add('#6 ERROR '+e.getMessage()); }

// #7 bulk 200 NF tasks in one transaction
try {
    List<Contact> cs = new List<Contact>();
    for (Integer i=0;i<200;i++) cs.add(new Contact(LastName='REV57_Bulk_'+i, AccountId=acct.Id));
    insert cs;
    List<Task> ts = new List<Task>();
    for (Integer i=0;i<200;i++) ts.add(new Task(Subject='NF - Bulk Sub '+i+' - Lexology - Free Newsfeed Subscriber - June 2026', WhoId=cs[i].Id, Status='Completed', Priority='Normal'));
    insert ts;
    Set<Id> cids = new Set<Id>(); for (Contact c : cs) cids.add(c.Id);
    Integer n = [SELECT COUNT() FROM Pardot_Form_Completion__c WHERE Contact__c IN :cids];
    r.add('#7 bulk 200 NF (expect 200): ' + (n==200 ? 'PASS' : 'FAIL n='+n));
} catch(Exception e){ r.add('#7 ERROR '+e.getMessage()); }

for (String s : r) System.debug('P4_RESULT '+s);
