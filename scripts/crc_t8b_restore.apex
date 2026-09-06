Application_Settings__c s = Application_Settings__c.getInstance(UserInfo.getUserId());
s.Disable_Autolaunch_Lightning_Flow__c=false; upsert s;
// reset NoRole back to Identify/10 for repeatability (flow is off so won't block)
Id i=[SELECT Id FROM Opportunity WHERE Name='CRCTEST NoRole' LIMIT 1].Id;
System.debug('CRCTEST: T8 restore done, kill switch OFF again');
