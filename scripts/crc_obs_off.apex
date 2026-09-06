Application_Settings__c s=Application_Settings__c.getInstance(UserInfo.getUserId());
s.Disable_Autolaunch_Lightning_Flow__c=false; s.Disable_Validation_Rules__c=false; upsert s;
System.debug('CRCTEST: OBS kill switch OFF (restored)');
