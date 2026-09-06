try { delete [SELECT Id FROM Flow_Log__c WHERE Error_Description__c='SIMULATED FAULT for observability test']; System.debug('CRCTEST: test flow logs deleted'); }
catch(Exception e){ System.debug('CRCTEST: flow log delete skipped: '+e.getMessage()); }
