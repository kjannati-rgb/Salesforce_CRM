Set<String> profs = new Set<String>{'System Administrator','ALM - Custom: Fin/Ops/HR','Custom: Fin/Ops/HR','B2BMA Integration User'};
Id bypassPs=[SELECT Id FROM PermissionSet WHERE Name='Contact_Role_Check_Bypass' LIMIT 1].Id;
Id flsPs=[SELECT Id FROM PermissionSet WHERE Name='CRC_Field_Access' LIMIT 1].Id;
Set<Id> hasBypass=new Set<Id>();
for(PermissionSetAssignment a:[SELECT AssigneeId FROM PermissionSetAssignment WHERE PermissionSetId=:bypassPs]) hasBypass.add(a.AssigneeId);
Set<Id> hasFls=new Set<Id>();
for(PermissionSetAssignment a:[SELECT AssigneeId FROM PermissionSetAssignment WHERE PermissionSetId=:flsPs]) hasFls.add(a.AssigneeId);
List<PermissionSetAssignment> toIns=new List<PermissionSetAssignment>();
for(User u:[SELECT Id, Profile.Name FROM User WHERE IsActive=true AND Profile.Name IN :profs]){
  if(!hasBypass.contains(u.Id)) toIns.add(new PermissionSetAssignment(PermissionSetId=bypassPs, AssigneeId=u.Id));
  if(u.Profile.Name=='System Administrator' && !hasFls.contains(u.Id)) toIns.add(new PermissionSetAssignment(PermissionSetId=flsPs, AssigneeId=u.Id));
}
Database.SaveResult[] rs=Database.insert(toIns,false);
Integer okc=0,fc=0; for(Database.SaveResult r:rs){ if(r.isSuccess()) okc++; else fc++; }
Integer chk=[SELECT COUNT() FROM PermissionSetAssignment WHERE PermissionSetId=:bypassPs];
Integer b2bma=[SELECT COUNT() FROM PermissionSetAssignment WHERE PermissionSetId=:bypassPs AND Assignee.Profile.Name='B2BMA Integration User'];
System.debug('CRCPROD: inserts ok='+okc+' fail='+fc+'; total bypass assignments now='+chk+'; B2BMA covered='+b2bma);
