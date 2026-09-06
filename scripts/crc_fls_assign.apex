Id psId=[SELECT Id FROM PermissionSet WHERE Name='CRC_Field_Access' LIMIT 1].Id;
Integer ex=[SELECT COUNT() FROM PermissionSetAssignment WHERE PermissionSetId=:psId AND AssigneeId=:UserInfo.getUserId()];
if(ex==0) insert new PermissionSetAssignment(PermissionSetId=psId, AssigneeId=UserInfo.getUserId());
System.debug('CRCTEST: FLS perm assigned (existing='+ex+')');
