Application_Settings__c s = Application_Settings__c.getInstance(UserInfo.getUserId());
if(s!=null && s.SetupOwnerId==UserInfo.getUserId()){ s.Disable_Validation_Rules__c=false; s.Disable_Autolaunch_Lightning_Flow__c=false; upsert s; }
System.debug('CRCTEST: CLEAN1b settings reset');
