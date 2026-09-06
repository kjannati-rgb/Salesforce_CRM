// Small backfill: set Product_Brand__c = Brand__c on recent OPEN records missing it.
// Open stages only (avoids Converted/Disqualified VRs); last 7 days; capped at 500.
List<Pardot_Form_Completion__c> recs = [
    SELECT Id, Brand__c, Product_Brand__c
    FROM Pardot_Form_Completion__c
    WHERE Product_Brand__c = null
      AND Sales_Stage__c IN ('New','Working','Nurturing')
      AND CreatedDate = LAST_N_DAYS:7
    LIMIT 500];
for (Pardot_Form_Completion__c p : recs) {
    p.Product_Brand__c = p.Brand__c;
}
try {
    update recs;
    System.debug('BACKFILL updated=' + recs.size());
} catch (Exception e) {
    System.debug('BACKFILL ERROR (' + recs.size() + ' candidates): ' + e.getMessage());
}
