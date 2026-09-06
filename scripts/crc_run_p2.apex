Id jid = Database.executeBatch(new ContactRoleCheckRecompute('IsClosed = false'), 50);
System.debug('CRCBATCH: phase2 jobId='+jid);
