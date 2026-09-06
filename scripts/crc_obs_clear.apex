Opportunity o=[SELECT Id FROM Opportunity WHERE Name='CRCTEST Obs' LIMIT 1];
Integer b0=[SELECT COUNT() FROM Flow_Log__c WHERE Flow_Name__c='Check Completeness of Contact Roles'];
update new Opportunity(Id=o.Id, StageName='Identify', Probability=10); // enabled flow -> Clear_Error runs
Opportunity r=[SELECT Contact_Role_Check_Has_Error__c FROM Opportunity WHERE Id=:o.Id];
Integer aft=[SELECT COUNT() FROM Flow_Log__c WHERE Flow_Name__c='Check Completeness of Contact Roles'];
System.debug('CRCTEST: OBS clean-save HasError='+r.Contact_Role_Check_Has_Error__c+' (expect false); logs '+b0+'->'+aft+' (expect no change)');
