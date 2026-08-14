/**
 * MatchDomainBackfill
 * -------------------
 * Populates Account.Match_Domain__c (the indexed key the matcher relies on) from a
 * cascade of existing signals, so exact-domain matching actually hits:
 *   1. Groove domains (DaScoopComposer__Domain_1/2__c)   ~65% coverage in prod
 *   2. Website host                                       ~49%
 *   3. Modal non-free-mail domain of the account's Contacts  (1.3M contacts)
 *   4. Approved_Email_Domain__c                           (sparse, but trusted)
 * Free-mail domains are never used as a firm key (LeadMatchSelectService.domainKey).
 *
 * Batchable + Stateful so it scales over ~740k accounts. Best-effort updates.
 */
public with sharing class MatchDomainBackfill implements Database.Batchable<SObject>, Database.Stateful {

    public Integer scanned = 0;
    public Integer stamped = 0;

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Name, Match_Domain__c, Match_Name__c, Website, Approved_Email_Domain__c,
                   DaScoopComposer__Domain_1__c, DaScoopComposer__Domain_2__c
            FROM Account
            WHERE (Match_Domain__c = null OR Match_Name__c = null)
              AND RecordType.DeveloperName IN ('Firm', 'Office')
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Account> scope) {
        scanned += scope.size();
        Map<Id, Account> toStamp = new Map<Id, Account>();
        List<Id> needContacts = new List<Id>();

        // Pass 1: domain from field signals (Groove / Website / Approved) + normalised name.
        for (Account a : scope) {
            Account upd = new Account(Id = a.Id);
            Boolean changed = false;
            if (a.Match_Domain__c == null) {
                String d = fromFields(a);
                if (d != null) { upd.Match_Domain__c = d; changed = true; }
                else needContacts.add(a.Id);
            }
            if (a.Match_Name__c == null) {
                String n = normalizeFirmName(a.Name);
                if (n != null) { upd.Match_Name__c = n; changed = true; }
            }
            if (changed) toStamp.put(a.Id, upd);
        }

        // Pass 2: modal non-free-mail contact-email domain for the rest.
        if (!needContacts.isEmpty()) {
            Map<Id, Map<String, Integer>> tally = new Map<Id, Map<String, Integer>>();
            for (Contact c : [
                SELECT AccountId, Email FROM Contact
                WHERE AccountId IN :needContacts AND Email != null
            ]) {
                String d = LeadMatchSelectService.domainKey(c.Email, null);
                if (d == null) continue;
                if (!tally.containsKey(c.AccountId)) tally.put(c.AccountId, new Map<String, Integer>());
                Map<String, Integer> m = tally.get(c.AccountId);
                m.put(d, (m.containsKey(d) ? m.get(d) : 0) + 1);
            }
            for (Id acc : tally.keySet()) {
                String best = null;
                Integer bestN = 0;
                for (String d : tally.get(acc).keySet()) {
                    if (tally.get(acc).get(d) > bestN) { bestN = tally.get(acc).get(d); best = d; }
                }
                if (best != null) {
                    Account upd = toStamp.containsKey(acc) ? toStamp.get(acc) : new Account(Id = acc);
                    upd.Match_Domain__c = best;
                    toStamp.put(acc, upd);
                }
            }
        }

        if (!toStamp.isEmpty()) {
            Database.update(toStamp.values(), false);   // best-effort; skip row failures
            stamped += toStamp.size();
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('MatchDomainBackfill: scanned ' + scanned + ', stamped ' + stamped);
    }

    // Legal-entity suffixes stripped from the name key (kept conservative — does NOT strip
    // entity-distinguishing words like "international"/"group"/"holdings").
    private static final Set<String> SUFFIXES = new Set<String>{
        'llp','llc','inc','incorporated','ltd','limited','plc','lp','pllc','pc','sa','sas','sarl',
        'gmbh','ag','bv','nv','srl','spa','kg','pty','corp','corporation','oy','ab','as','co'
    };

    @TestVisible
    public static String normalizeFirmName(String name) {
        if (String.isBlank(name)) return null;
        String s = name.toLowerCase().replaceAll('[^a-z0-9 ]', ' ').replaceAll('\\s+', ' ').trim();
        List<String> words = new List<String>();
        for (String w : s.split(' ')) {
            if (String.isBlank(w)) continue;
            if (w == 'the' && words.isEmpty()) continue;   // drop leading "the"
            if (SUFFIXES.contains(w)) continue;
            words.add(w);
        }
        String result = String.join(words, ' ').trim();
        return String.isBlank(result) ? null : result;
    }

    @TestVisible
    private static String fromFields(Account a) {
        for (String raw : new List<String>{
            a.DaScoopComposer__Domain_1__c, a.DaScoopComposer__Domain_2__c, a.Website
        }) {
            String d = LeadMatchSelectService.domainKey(null, raw);
            if (d != null) return d;
        }
        if (String.isNotBlank(a.Approved_Email_Domain__c)) return a.Approved_Email_Domain__c.trim().toLowerCase();
        return null;
    }
}
