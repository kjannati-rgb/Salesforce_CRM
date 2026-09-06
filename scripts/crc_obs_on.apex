Application_Settings__c s=Application_Settings__c.getInstance(UserInfo.getUserId());
if(s==null||s.SetupOwnerId!=UserInfo.getUserId()) s=new Application_Settings__c(SetupOwnerId=UserInfo.getUserId());
s.Disable_Autolaunch_Lightning_Flow__c=true; s.Disable_Validation_Rules__c=true; upsert s;
System.debug('CRCTEST: OBS kill switch ON');
