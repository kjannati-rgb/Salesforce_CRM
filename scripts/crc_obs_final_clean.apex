delete [SELECT Id FROM Opportunity WHERE Name LIKE 'CRCTEST%'];
delete [SELECT Id FROM Account WHERE Name LIKE 'CRCTEST%'];
delete [SELECT Id FROM Flow_Log__c WHERE Record_Name__c='CRCTEST Obs'];
Application_Settings__c s=Application_Settings__c.getInstance(UserInfo.getUserId());
if(s!=null && s.SetupOwnerId==UserInfo.getUserId()){ s.Disable_Autolaunch_Lightning_Flow__c=false; s.Disable_Validation_Rules__c=false; upsert s; }
System.debug('CRCTEST: FINAL CLEAN done; opps='+[SELECT COUNT() FROM Opportunity WHERE Name LIKE 'CRCTEST%']);
