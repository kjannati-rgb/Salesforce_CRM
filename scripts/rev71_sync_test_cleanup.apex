// REV-71 — Step 2 sync verification CLEANUP: removes the ZZ REV71-SYNC-01 scaffold
// (account cascade-deletes opportunity, quote, lines, OLIs). Run only on request.

List<Account> accs = [SELECT Id FROM Account WHERE Name = 'ZZ REV71 Sync Test Account'];
delete accs;
System.debug('REV71_CLEANUP deleted accounts=' + accs.size());
