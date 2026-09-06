// assign bypass perm set to me (if not already), then update incomplete opp @75 -> expect SAVED
Id psId=[SELECT Id FROM PermissionSet WHERE Name='CRC_Bypass_Test' LIMIT 1].Id;
Integer existing=[SELECT COUNT() FROM PermissionSetAssignment WHERE PermissionSetId=:psId AND AssigneeId=:UserInfo.getUserId()];
if(existing==0) insert new PermissionSetAssignment(PermissionSetId=psId, AssigneeId=UserInfo.getUserId());
System.debug('CRCTEST: T10 bypass assigned (existing='+existing+')');
