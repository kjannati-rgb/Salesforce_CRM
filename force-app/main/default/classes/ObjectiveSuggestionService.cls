/**
 * Proposes Account Plan objectives from the live data — gap-to-benchmark headroom and open signals —
 * so plan leads accept them with one click instead of authoring from scratch. Read-only suggestion
 * pass (nothing persisted until accept()); deduped against existing objectives.
 */
public with sharing class ObjectiveSuggestionService {

    private static final Decimal HEADROOM_FLOOR = 25000; // ignore trivial gaps
    private static final Set<String> SIGNAL_TYPES = new Set<String>{ 'Expansion', 'Risk', 'Churn' };

    public class Suggestion {
        @AuraEnabled public String key;          // stable id for the UI + accept()
        @AuraEnabled public String title;
        @AuraEnabled public String rationale;
        @AuraEnabled public Decimal targetAmount;
        @AuraEnabled public Id linkedFamilyId;
        @AuraEnabled public String source;       // 'Headroom' | 'Signal'
    }

    @AuraEnabled(cacheable=true)
    public static List<Suggestion> suggest(Id planId) {
        List<Suggestion> result = new List<Suggestion>();
        if (planId == null) {
            return result;
        }

        // Dedupe against what the plan already pursues.
        Set<Id> coveredFamilies = new Set<Id>();
        Set<String> existingTitles = new Set<String>();
        for (Plan_Objective__c o : [
            SELECT Linked_Family__c, Name FROM Plan_Objective__c WHERE Account_Plan__c = :planId
        ]) {
            if (o.Linked_Family__c != null) coveredFamilies.add(o.Linked_Family__c);
            if (o.Name != null) existingTitles.add(o.Name.toLowerCase());
        }

        // 1) Headroom by product family across the plan's gap cells.
        Map<Id, Decimal> headroomByFamily = new Map<Id, Decimal>();
        Map<Id, String> familyName = new Map<Id, String>();
        Map<Id, Set<String>> nodesByFamily = new Map<Id, Set<String>>();
        for (Whitespace_Cell__c c : [
            SELECT Product_Family__c, Product_Family__r.Name, Expected_Revenue__c, Node_Label__c
            FROM Whitespace_Cell__c
            WHERE Account_Plan__c = :planId AND Expected_Revenue__c > 0
        ]) {
            Id fid = c.Product_Family__c;
            headroomByFamily.put(fid, (headroomByFamily.containsKey(fid) ? headroomByFamily.get(fid) : 0) + c.Expected_Revenue__c);
            familyName.put(fid, c.Product_Family__r.Name);
            if (!nodesByFamily.containsKey(fid)) {
                nodesByFamily.put(fid, new Set<String>());
            }
            nodesByFamily.get(fid).add(c.Node_Label__c);
        }
        for (Id fid : headroomByFamily.keySet()) {
            Decimal hr = headroomByFamily.get(fid);
            if (hr < HEADROOM_FLOOR || coveredFamilies.contains(fid)) {
                continue;
            }
            Integer nodeCount = nodesByFamily.get(fid).size();
            Suggestion s = new Suggestion();
            s.key = 'HR|' + fid;
            s.title = 'Convert ' + money(hr) + ' ' + familyName.get(fid) + ' white space';
            s.rationale = money(hr) + ' gap-to-benchmark across ' + nodeCount + ' node' + (nodeCount == 1 ? '' : 's');
            s.targetAmount = hr;
            s.linkedFamilyId = fid;
            s.source = 'Headroom';
            result.add(s);
        }

        // 2) Open expansion / risk / churn signals.
        for (Plan_Signal__c sig : [
            SELECT Id, Signal_Type__c, Summary__c, Recommended_Action__c
            FROM Plan_Signal__c
            WHERE Account_Plan__c = :planId AND Status__c = 'Open' AND Signal_Type__c IN :SIGNAL_TYPES
        ]) {
            String verb = (sig.Signal_Type__c == 'Expansion') ? 'Pursue: ' : 'Mitigate: ';
            String title = verb + sig.Summary__c;
            if (title.length() > 80) {
                title = title.substring(0, 80);
            }
            if (existingTitles.contains(title.toLowerCase())) {
                continue;
            }
            Suggestion s = new Suggestion();
            s.key = 'SIG|' + sig.Id;
            s.title = title;
            s.rationale = 'From ' + sig.Signal_Type__c + ' signal'
                + (String.isNotBlank(sig.Recommended_Action__c) ? ' — ' + sig.Recommended_Action__c : '');
            s.source = 'Signal';
            result.add(s);
        }

        return result;
    }

    /** Persist an accepted suggestion as a new Plan_Objective__c. @return the new objective Id. */
    @AuraEnabled
    public static Id accept(Id planId, String title, Decimal targetAmount, Id linkedFamilyId) {
        if (planId == null || String.isBlank(title)) {
            throw new AuraHandledException('A plan and title are required.');
        }
        Plan_Objective__c o = new Plan_Objective__c(
            Account_Plan__c = planId,
            Name = title.length() > 80 ? title.substring(0, 80) : title,
            Status__c = 'Not_Started',
            Progress_Pct__c = 0,
            Target_Amount__c = targetAmount,
            Linked_Family__c = linkedFamilyId,
            Due_Date__c = Date.today().addDays(90));
        insert o;
        return o.Id;
    }

    private static String money(Decimal n) {
        if (n == null) return '£0';
        if (n >= 1000000) return '£' + (n / 1000000).setScale(2) + 'M';
        if (n >= 1000) return '£' + (n / 1000).setScale(0) + 'K';
        return '£' + n.setScale(0);
    }
}
