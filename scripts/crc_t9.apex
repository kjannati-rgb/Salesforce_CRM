Id NB=[SELECT Id FROM RecordType WHERE SobjectType='Opportunity' AND DeveloperName='New_Business' LIMIT 1].Id;
Date CD=Date.today().addMonths(2);
Id accOk=[SELECT Id FROM Account WHERE Name='CRCTEST Acc OK' LIMIT 1].Id;
Id conOk=[SELECT Id FROM Contact WHERE LastName='CRCTEST Complete' LIMIT 1].Id;
delete [SELECT Id FROM Opportunity WHERE Name LIKE 'CRCTEST Bulk%'];
Opportunity[] oppList=new Opportunity[]{};
for(Integer i=0;i<60;i++) oppList.add(new Opportunity(Name='CRCTEST Bulk '+i,AccountId=accOk,StageName='Identify',Probability=10,CloseDate=CD,RecordTypeId=NB));
insert oppList;
OpportunityContactRole[] ocrs=new OpportunityContactRole[]{};
for(Integer j=0;j<30;j++) ocrs.add(new OpportunityContactRole(OpportunityId=oppList[j].Id,ContactId=conOk,IsPrimary=true,Role='Decision Maker'));
insert ocrs;
for(Opportunity o:oppList){ o.StageName='Negotiate'; o.Probability=75; }
Database.SaveResult[] srs=Database.update(oppList,false);
Integer ok=0,fail=0; for(Database.SaveResult sr:srs){ if(sr.isSuccess()) ok++; else fail++; }
System.debug('CRCTEST: T9 BULK 60 (30 complete/30 norole) => success='+ok+' fail='+fail+' (expect 30/30); SOQL='+Limits.getQueries()+'/'+Limits.getLimitQueries());
