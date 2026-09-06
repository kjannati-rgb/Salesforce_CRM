List<String> out = new List<String>();
String RT_FC = '012Tm000000xaVhIAI';
String RT_NF = '012Px000003AadBIAS';

// ---- light cleanup of today's test clutter ----
try { delete [SELECT Id FROM Pardot_Form_Completion__c WHERE CreatedDate = TODAY]; } catch(Exception e){ out.add('cleanup PFC: '+e.getMessage()); }
try { delete [SELECT Id FROM Task WHERE CreatedDate = TODAY AND (Subject LIKE 'NF -%' OR Subject LIKE 'PFC:%' OR Subject LIKE 'EVT%' OR Subject LIKE '%Bulk%' OR Subject LIKE '%normal task%')]; } catch(Exception e){ out.add('cleanup Task: '+e.getMessage()); }
try { delete [SELECT Id FROM Contact WHERE LastName LIKE 'REV57%']; } catch(Exception e){ out.add('cleanup Contact: '+e.getMessage()); }
try { delete [SELECT Id FROM Lead WHERE LastName LIKE 'REV57%' AND IsConverted = false]; } catch(Exception e){ out.add('cleanup Lead: '+e.getMessage()); }
try { delete [SELECT Id FROM Account WHERE Name LIKE 'REV57%']; } catch(Exception e){ out.add('cleanup Acct: '+e.getMessage()); }

// ---- DEMO A: forward cross-link (Newsfeed -> existing open inbound, same person + Lexology) ----
Account aA = new Account(Name='Demo Corp Alpha'); insert aA;
Contact ca = new Contact(FirstName='Aisha', LastName='Patel (DEMO A)', AccountId=aA.Id); insert ca;
Pardot_Form_Completion__c inbA = new Pardot_Form_Completion__c(Name='DEMO A - Inbound Lexology enquiry', RecordTypeId=RT_FC, Contact__c=ca.Id, Product_Brand__c='Lexology', PFC_Source__c='Inbound Form', Sales_Stage__c='Working'); insert inbA;
insert new Task(Subject='NF - Aisha Patel - Lexology - Free Newsfeed Subscriber - June 2026', WhoId=ca.Id, Status='Completed', Priority='Normal');
Pardot_Form_Completion__c nfA = [SELECT Id, Related_Form_Completion__c FROM Pardot_Form_Completion__c WHERE Contact__c=:ca.Id AND RecordTypeId=:RT_NF LIMIT 1];
out.add('A_NF_PFC=' + nfA.Id + ' linkedTo=' + nfA.Related_Form_Completion__c + ' expect=' + inbA.Id);
out.add('A_INBOUND_PFC=' + inbA.Id);

// ---- DEMO B: reverse (inbound -> existing open newsfeed) ----
Account aB = new Account(Name='Demo Corp Bravo'); insert aB;
Contact cb = new Contact(FirstName='Ben', LastName='Carter (DEMO B)', AccountId=aB.Id); insert cb;
insert new Task(Subject='NF - Ben Carter - Lexology - Free Newsfeed Subscriber - June 2026', WhoId=cb.Id, Status='Completed', Priority='Normal');
Pardot_Form_Completion__c nfB = [SELECT Id FROM Pardot_Form_Completion__c WHERE Contact__c=:cb.Id AND RecordTypeId=:RT_NF LIMIT 1];
insert new Task(Subject='PFC: Lexology Subscriber Demo', WhoId=cb.Id, Status='Completed', Priority='Normal');
Pardot_Form_Completion__c inbB = [SELECT Id, Related_Form_Completion__c FROM Pardot_Form_Completion__c WHERE Contact__c=:cb.Id AND RecordTypeId=:RT_FC LIMIT 1];
out.add('B_INBOUND_PFC=' + inbB.Id + ' linkedTo=' + inbB.Related_Form_Completion__c + ' expect=' + nfB.Id);
out.add('B_NF_PFC=' + nfB.Id);

// ---- DEMO C: conversion relink (left UN-converted for a live click) ----
Lead lc = new Lead(FirstName='Clara', LastName='Nantes (DEMO C)', Company='Demo Corp Charlie'); insert lc;
Pardot_Form_Completion__c pfcC = new Pardot_Form_Completion__c(Name='DEMO C - pre-conversion', RecordTypeId=RT_FC, Lead__c=lc.Id, Product_Brand__c='Lexology', Sales_Stage__c='New'); insert pfcC;
out.add('C_LEAD=' + lc.Id + ' C_PFC=' + pfcC.Id);

for (String s : out) System.debug('DEMO_OUT ' + s);
