Application_Settings__c s = Application_Settings__c.getInstance(UserInfo.getUserId());
if (s==null || s.SetupOwnerId!=UserInfo.getUserId()) s=new Application_Settings__c(SetupOwnerId=UserInfo.getUserId());
s.Disable_Autolaunch_Lightning_Flow__c=true; s.Disable_Validation_Rules__c=true; upsert s;
Id i=[SELECT Id FROM Opportunity WHERE Name='CRCTEST NoRole' LIMIT 1].Id;
try{ update new Opportunity(Id=i,StageName='Negotiate',Probability=75); System.debug('CRCTEST: T8 killswitch norole@75 => SAVED (expected, flow off)'); }
catch(Exception e){ System.debug('CRCTEST: T8 killswitch => BLOCKED (UNEXPECTED): '+e.getMessage()); }
