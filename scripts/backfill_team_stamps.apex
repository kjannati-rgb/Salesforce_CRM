Map<Id,Id> cedByOpp = new Map<Id,Id>();
for (OpportunityTeamMember t : [SELECT OpportunityId, UserId FROM OpportunityTeamMember
        WHERE TeamMemberRole='Client Engagement Director' AND Opportunity.Client_Engagement_Director__c = null]) {
    cedByOpp.put(t.OpportunityId, t.UserId);
}
Map<Id,Id> sdrByOpp = new Map<Id,Id>();
for (OpportunityTeamMember t : [SELECT OpportunityId, UserId FROM OpportunityTeamMember
        WHERE TeamMemberRole='Sales Development Representative' AND Opportunity.Sales_Development_Representative__c = null]) {
    sdrByOpp.put(t.OpportunityId, t.UserId);
}
Map<Id,Opportunity> ops = new Map<Id,Opportunity>();
for (Id oid : cedByOpp.keySet()) ops.put(oid, new Opportunity(Id=oid, Client_Engagement_Director__c=cedByOpp.get(oid)));
for (Id oid : sdrByOpp.keySet()) {
    Opportunity o = ops.containsKey(oid) ? ops.get(oid) : new Opportunity(Id=oid);
    o.Sales_Development_Representative__c = sdrByOpp.get(oid);
    ops.put(oid, o);
}
List<Opportunity> updates = ops.values();
System.debug('PLAN: '+updates.size()+' opps to stamp (CED='+cedByOpp.size()+' SDR='+sdrByOpp.size()+')');
for (Opportunity o : updates) System.debug('STAMP '+o.Id+' CED='+o.Client_Engagement_Director__c+' SDR='+o.Sales_Development_Representative__c);
Database.SaveResult[] rs = Database.update(updates, false);
Integer ok=0, fail=0;
for (Integer i=0; i<rs.size(); i++) {
    if (rs[i].isSuccess()) ok++;
    else { fail++; System.debug('FAIL '+updates[i].Id+' : '+rs[i].getErrors()[0].getMessage()); }
}
System.debug('BACKFILL_DONE ok='+ok+' fail='+fail);
