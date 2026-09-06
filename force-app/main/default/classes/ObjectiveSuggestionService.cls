/**
 * Proposes Account Plan objectives from open Plan_Signal__c records — so plan leads accept them with
 * one click instead of authoring from scratch. Read-only suggestion pass (nothing persisted until
 * accept()); deduped against existing objectives.
 */
public with sharing class ObjectiveSuggestionService {

    private static final Set<String> SIGNAL_TYPES = new Set<String>{ 'Expansion', 'Risk', 'Churn' };

    public class Suggestion {
        @AuraEnabled public String key;          // stable id for the UI + accept()
        @AuraEnabled public String title;
        @AuraEnabled public String rationale;
        @AuraEnabled public Decimal targetAmount;
        @AuraEnabled public Id linkedFamilyId;
        @AuraEnabled public String source;       // 'Signal'
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

        // Open expansion / risk / churn signals.
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
}
