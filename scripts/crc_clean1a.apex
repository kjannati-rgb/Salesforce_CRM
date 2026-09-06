delete [SELECT Id FROM PermissionSetAssignment WHERE PermissionSet.Name='CRC_Bypass_Test' AND AssigneeId=:UserInfo.getUserId()];
System.debug('CRCTEST: CLEAN1a perm unassigned');
