// REV-71 §6 matrix TEARDOWN — deletes ALL ZZ REV71-M* scenario accounts
// (cascade removes opps, quotes, lines, OLIs). Run only on explicit request.
// Deletes in batches of 10 to respect the org's heavy Opportunity automation.
List<Account> accs = [SELECT Id FROM Account WHERE Name LIKE 'ZZ REV71-M%' LIMIT 10];
delete accs;
System.debug('REV71_MX_TEARDOWN deleted=' + accs.size() + ' (re-run until 0)');
