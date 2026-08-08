// Diagnose the Opportunity Contact Role dup-check: is the 64-error signal a genuine
// fault, or the Custom Error duplicate-block firing as designed? Build a minimal stack,
// then attempt a duplicate role and report exactly what happens. KJDEV sandbox.
String tag = 'ZZ OCR-REPRO';
Account a = new Account(Name = tag + ' Acct'); insert a;
Contact c = new Contact(LastName = tag + ' Contact', AccountId = a.Id); insert c;
Opportunity o = new Opportunity(Name = tag + ' Opp', AccountId = a.Id, StageName = 'Qualify',
    CloseDate = Date.today().addDays(30)); insert o;

// First contact role — should succeed
OpportunityContactRole r1 = new OpportunityContactRole(
    OpportunityId = o.Id, ContactId = c.Id, Role = 'Decision Maker');
insert r1;
System.debug('OCR_REPRO first role inserted: ' + r1.Id);

// Duplicate (same opp + contact + role) — the flow should block this if it's working as designed
try {
    OpportunityContactRole r2 = new OpportunityContactRole(
        OpportunityId = o.Id, ContactId = c.Id, Role = 'Decision Maker');
    insert r2;
    System.debug('OCR_REPRO DUPLICATE INSERTED with no block: ' + r2.Id + ' (flow did NOT stop it)');
} catch (Exception e) {
    System.debug('OCR_REPRO duplicate blocked -> ' + e.getTypeName() + ': ' + e.getMessage());
}
