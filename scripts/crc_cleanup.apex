delete [SELECT Id FROM Opportunity WHERE Name LIKE 'CRCTEST%'];
delete [SELECT Id FROM Contact WHERE LastName LIKE 'CRCTEST%'];
delete [SELECT Id FROM Account WHERE Name LIKE 'CRCTEST%'];
delete [SELECT Id FROM PermissionSetAssignment WHERE PermissionSet.Name='CRC_Bypass_Test' AND AssigneeId=:UserInfo.getUserId()];
Application_Settings__c s = Application_Settings__c.getInstance(UserInfo.getUserId());
if(s!=null && s.SetupOwnerId==UserInfo.getUserId()){ s.Disable_Validation_Rules__c=false; s.Disable_Autolaunch_Lightning_Flow__c=false; upsert s; }
System.debug('CRCTEST: CLEANUP DONE');
