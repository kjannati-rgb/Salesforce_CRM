Id jid = Database.executeBatch(new ContactRoleCheckRecompute('IsClosed = false AND Probability >= 50'), 50);
System.debug('CRCBATCH: phase1 jobId='+jid);
