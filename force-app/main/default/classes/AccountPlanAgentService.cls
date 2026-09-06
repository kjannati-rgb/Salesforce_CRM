/**
 * Agentforce / Flow / Prompt-Builder grounding action: returns a concise natural-language white-space
 * summary for an Account Plan (firm, owned ARR, coverage, open signals, suggested plays). Surfacing
 * the object-backed plan data as grounded text an LLM can reason over.
 */
public with sharing class AccountPlanAgentService {

    public class Request {
        @InvocableVariable(label='Account Plan ID' description='The Account_Plan__c record to summarize' required=true)
        public Id planId;
    }

    public class Response {
        @InvocableVariable(label='Summary' description='Natural-language white-space summary')
        public String summary;
    }

    @InvocableMethod(label='Summarize Account Plan White Space'
                     description='Grounded white-space summary (owned ARR, coverage, signals, suggested plays) for an account plan')
    public static List<Response> summarize(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request r : requests) {
            Response resp = new Response();
            resp.summary = buildSummary(r == null ? null : r.planId);
            responses.add(resp);
        }
        return responses;
    }

    private static String buildSummary(Id planId) {
        if (planId == null) {
            return 'No account plan specified.';
        }
        List<Account_Plan__c> plans = [
            SELECT Id, Name, Account__r.Name, Segment__c, Plan_Tier__c,
                   Total_ARR__c, Family_Coverage_Pct__c
            FROM Account_Plan__c WHERE Id = :planId LIMIT 1
        ];
        if (plans.isEmpty()) {
            return 'Account plan not found.';
        }
        Account_Plan__c p = plans[0];

        Integer openSignals = [
            SELECT COUNT() FROM Plan_Signal__c WHERE Account_Plan__c = :planId AND Status__c = 'Open'
        ];

        List<String> plays = new List<String>();
        for (ObjectiveSuggestionService.Suggestion s : ObjectiveSuggestionService.suggest(planId)) {
            if (plays.size() >= 3) break;
            plays.add(s.title);
        }

        String firm = (p.Account__r != null && p.Account__r.Name != null) ? p.Account__r.Name : p.Name;
        List<String> descParts = new List<String>();
        if (String.isNotBlank(p.Segment__c)) descParts.add(p.Segment__c);
        if (String.isNotBlank(p.Plan_Tier__c)) descParts.add(p.Plan_Tier__c);
        String descriptor = String.join(descParts, ', ');

        String out = firm + (String.isBlank(descriptor) ? '' : ' (' + descriptor + ')') + ': '
            + money(p.Total_ARR__c) + ' owned ARR'
            + (p.Family_Coverage_Pct__c != null ? ' at ' + p.Family_Coverage_Pct__c + '% family coverage' : '') + '. ';
        out += openSignals + ' open signal' + (openSignals == 1 ? '' : 's') + '. ';
        if (!plays.isEmpty()) {
            out += 'Suggested plays: ' + String.join(plays, '; ') + '.';
        }
        return out;
    }

    private static String money(Decimal n) {
        if (n == null) return '£0';
        if (n >= 1000000) return '£' + (n / 1000000).setScale(2) + 'M';
        if (n >= 1000) return '£' + (n / 1000).setScale(0) + 'K';
        return '£' + n.setScale(0);
    }
}
