/**
 * LeadMatchSelectService
 * -----------------------
 * Single match-and-select engine for World-Class Lead Conversion (see
 * ClaudeCode_PhaseC_Lead_Conversion_Architecture.md). Called by both conversion
 * doors (native convert Screen Flow + Pardot form-completion).
 *
 * Contract: PURE RESOLUTION, NO DML. Callers own all writes so the engine never
 * trips DupeBlocker / AddressTools. Bulk-safe: a fixed handful of SOQL regardless
 * of batch size.
 *
 * v1 scope: company -> Firm resolution by indexed domain equality, then Office
 * ranking (location primary, opportunity rollups as tiebreaker), confidence
 * tiering, existing-customer flag. Contact-level dedup is a fast-follow (C-phase).
 */
public with sharing class LeadMatchSelectService {

    // ---- Invocable I/O -----------------------------------------------------

    public class Request {
        @InvocableVariable(label='Record Id (Lead or Form)') public Id recordId;
        @InvocableVariable(label='Email') public String email;
        @InvocableVariable(label='Company') public String company;
        @InvocableVariable(label='Country Code') public String countryCode;
        @InvocableVariable(label='Region') public String region;
        @InvocableVariable(label='Website') public String website;
    }

    public class CandidateOffice {
        @InvocableVariable public Id officeId;
        @InvocableVariable public String name;
        @InvocableVariable public String billingCountryCode;
        @InvocableVariable public String billingCity;
        @InvocableVariable public Double wonOppCount;
        @InvocableVariable public Double wonOppValue;
        @InvocableVariable public Double cfyWonOppCount;
        @InvocableVariable public Double activeContacts;
        @InvocableVariable public Double locationScore;
        @InvocableVariable public Boolean addressValid;
        @InvocableVariable public String evidence;
    }

    public class Result {
        @InvocableVariable public Id resolvedFirmId;
        @InvocableVariable public String resolvedFirmName;
        @InvocableVariable public List<Id> candidateFirmIds;   // populated when a domain maps to 2+ Firms
        @InvocableVariable public Id recommendedOfficeId;
        @InvocableVariable public String recommendedOfficeName;
        @InvocableVariable public List<CandidateOffice> candidateOffices;
        @InvocableVariable public List<Id> candidateOfficeIds;   // ranked, for a Flow choice set
        @InvocableVariable public String candidateSummary;       // ranked, human-readable evidence
        @InvocableVariable public String confidenceTier;   // ONECLICK / REVIEW / GUIDED_CREATE
        @InvocableVariable public Boolean matchedViaWebsite; // firm found via the lead's website host, not the email domain
        @InvocableVariable public Boolean conflict;
        @InvocableVariable public Boolean existingCustomer;
        @InvocableVariable public String matchEvidence;
    }

    // ---- Free-mail domains we never treat as a firm key --------------------
    // Hardcoded baseline (safety net if the CMDT isn't deployed); extended by Free_Mail_Domain__mdt.
    @TestVisible
    static final Set<String> BASE_FREE_MAIL = new Set<String>{
        'gmail.com','googlemail.com','yahoo.com','yahoo.co.uk','hotmail.com','hotmail.co.uk',
        'outlook.com','aol.com','icloud.com','live.com','msn.com','protonmail.com',
        'proton.me','gmx.com','mail.com','yandex.com','me.com'
    };
    static Set<String> freeMailCache;

    @TestVisible
    static Set<String> freeMail() {
        if (freeMailCache == null) {
            freeMailCache = new Set<String>(BASE_FREE_MAIL);
            for (Free_Mail_Domain__mdt m : Free_Mail_Domain__mdt.getAll().values()) {
                if (String.isNotBlank(m.Domain__c)) freeMailCache.add(m.Domain__c.trim().toLowerCase());
            }
        }
        return freeMailCache;
    }

    // ---- Entry point -------------------------------------------------------

    @InvocableMethod(label='Match and Select Account'
                     description='Resolve a lead/form to a Firm and ranked Offices (no DML).')
    public static List<Result> matchAndSelect(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null || requests.isEmpty()) return results;

        // 1) Derive domain keys per request: the email domain (primary) plus, when it differs,
        // the website host as a secondary key - people often email from an alias domain while
        // the lead form carries the canonical website (e.g. @victoria.com vs victoriassecret.com).
        List<String> perReqDomain = new List<String>();
        List<String> perReqSecondary = new List<String>();
        Set<String> domains = new Set<String>();
        for (Request r : requests) {
            String dom = extractDomain(r);
            String dom2 = secondaryDomain(r, dom);
            perReqDomain.add(dom);
            perReqSecondary.add(dom2);
            if (dom != null) domains.add(dom);
            if (dom2 != null) domains.add(dom2);
        }

        // 2) One query: accounts whose domain key matches (Office or Firm).
        Map<String, List<Account>> domainToAccounts = new Map<String, List<Account>>();
        Set<Id> firmIds = new Set<Id>();
        if (!domains.isEmpty()) {
            for (Account a : [
                SELECT Id, Name, RecordType.DeveloperName, Ultimate_Account__c, Ultimate_Account__r.Name,
                       Match_Domain__c, Approved_Email_Domain__c
                FROM Account
                WHERE Match_Domain__c IN :domains OR Approved_Email_Domain__c IN :domains
            ]) {
                addToDomainMap(domainToAccounts, normalize(a.Match_Domain__c), a);
                addToDomainMap(domainToAccounts, normalize(a.Approved_Email_Domain__c), a);
                Id fid = firmIdOf(a);
                if (fid != null) firmIds.add(fid);
            }
        }

        // 3) One query: all Offices under every resolved Firm, with ranking fields.
        Map<Id, List<Account>> firmToOffices = new Map<Id, List<Account>>();
        if (!firmIds.isEmpty()) {
            for (Account o : [
                SELECT Id, Name, BillingCountryCode, BillingCity, Ultimate_Account__c,
                       No_of_Won_Office_Opportunities__c, Val_of_Won_Office_Opportunities__c,
                       CFY_No_of_Won_Office_Opportunities__c, No_of_Active_Office_Contacts__c
                FROM Account
                WHERE RecordType.DeveloperName = 'Office' AND Ultimate_Account__c IN :firmIds
            ]) {
                if (!firmToOffices.containsKey(o.Ultimate_Account__c)) {
                    firmToOffices.put(o.Ultimate_Account__c, new List<Account>());
                }
                firmToOffices.get(o.Ultimate_Account__c).add(o);
            }
        }

        // 4) Build a result per request.
        for (Integer i = 0; i < requests.size(); i++) {
            results.add(buildResult(requests[i], perReqDomain[i], perReqSecondary[i], domainToAccounts, firmToOffices));
        }
        return results;
    }

    // ---- Per-request resolution -------------------------------------------

    private static Result buildResult(Request r, String dom, String dom2,
                                      Map<String, List<Account>> domainToAccounts,
                                      Map<Id, List<Account>> firmToOffices) {
        Result res = new Result();
        res.candidateOffices = new List<CandidateOffice>();
        res.conflict = false;
        res.existingCustomer = false;
        res.matchedViaWebsite = false;

        // Resolve the distinct set of Firms reachable from this request's domain.
        Set<Id> firmsForReq = new Set<Id>();
        String firmName = null;
        if (dom != null && domainToAccounts.containsKey(dom)) {
            for (Account a : domainToAccounts.get(dom)) {
                Id fid = firmIdOf(a);
                if (fid != null) { firmsForReq.add(fid); firmName = firmNameOf(a); }
            }
        }
        // Email domain unknown to us -> try the lead's website host as an exact secondary key.
        if (firmsForReq.isEmpty() && dom2 != null && domainToAccounts.containsKey(dom2)) {
            for (Account a : domainToAccounts.get(dom2)) {
                Id fid = firmIdOf(a);
                if (fid != null) { firmsForReq.add(fid); firmName = firmNameOf(a); }
            }
            res.matchedViaWebsite = !firmsForReq.isEmpty();
        }

        if (firmsForReq.isEmpty()) {
            res.confidenceTier = 'GUIDED_CREATE';
            res.matchEvidence = dom == null
                ? 'No usable domain key (free-mail or blank); company/name dedup required.'
                : 'No account matched domain "' + dom + '"'
                  + (dom2 != null ? ' or website "' + dom2 + '"' : '') + '; guided create.';
            return res;
        }
        if (firmsForReq.size() > 1) {
            res.confidenceTier = 'REVIEW';
            res.candidateFirmIds = new List<Id>(firmsForReq);
            res.matchEvidence = 'Domain "' + dom + '" resolves to ' + firmsForReq.size()
                + ' Firms; needs disambiguation.';
            return res;
        }

        // Single Firm resolved.
        Id firmId = new List<Id>(firmsForReq)[0];
        res.resolvedFirmId = firmId;
        res.resolvedFirmName = firmName;
        res.candidateFirmIds = new List<Id>{ firmId };

        List<Account> offices = firmToOffices.containsKey(firmId)
            ? firmToOffices.get(firmId) : new List<Account>();

        if (offices.isEmpty()) {
            res.confidenceTier = 'GUIDED_CREATE';
            res.matchEvidence = 'Firm matched but has no Office; create a new Office under this Firm.';
            return res;
        }

        // Score + rank Offices: location first, then opportunity rollups.
        // After sort, candidateOffices[0] is the best-location office and, among
        // offices sharing that location, the opportunity leader.
        for (Account o : offices) {
            res.candidateOffices.add(toCandidate(o, r));
        }
        res.candidateOffices.sort(new OfficeRanker());

        CandidateOffice rec = res.candidateOffices[0];
        res.recommendedOfficeId = rec.officeId;                   // location wins the recommendation
        res.recommendedOfficeName = rec.name;
        res.existingCustomer = (rec.wonOppCount != null && rec.wonOppCount > 0);

        // Expose the ranked candidates for an interactive Flow picker.
        res.candidateOfficeIds = new List<Id>();
        List<String> lines = new List<String>();
        for (CandidateOffice c : res.candidateOffices) {
            res.candidateOfficeIds.add(c.officeId);
            String tag = (c.officeId == rec.officeId) ? '  ← recommended' : '';
            lines.add('• ' + c.name + ' — won value ' + c.wonOppValue.format()
                + ', ' + String.valueOf(c.wonOppCount.intValue()) + ' opps'
                + (c.addressValid ? '' : ', ADDRESS INVALID') + tag);
        }
        res.candidateSummary = String.join(lines, '\n');

        // How many offices share the top location tier? (opportunity only breaks
        // ties AMONG location-equivalent offices.)
        Integer topLocCount = 0;
        for (CandidateOffice c : res.candidateOffices) {
            if (c.locationScore == rec.locationScore) topLocCount++;
        }

        // Conflict (the brief's dup-review case): another office that is ALSO
        // location-plausible (score > 0) but in a lower tier has more opportunity
        // weight than the recommendation -> likely a duplicate/near-by pair.
        CandidateOffice dupRisk = null;
        for (CandidateOffice c : res.candidateOffices) {
            if (c.officeId == rec.officeId) continue;
            if (c.locationScore > 0 && c.locationScore < rec.locationScore
                && c.wonOppValue > rec.wonOppValue) {
                dupRisk = c; break;
            }
        }

        if (dupRisk != null) {
            res.conflict = true;
            res.confidenceTier = 'REVIEW';
            res.matchEvidence = 'Location points to "' + rec.name + '" but a nearby Office "'
                + dupRisk.name + '" has more opportunities; flagged for dup review.';
        } else if (topLocCount > 1) {
            res.confidenceTier = 'REVIEW';
            res.matchEvidence = topLocCount + ' Offices share the best location ("' + rec.name
                + '" leads on opportunities); confirm before convert.';
        } else {
            res.confidenceTier = 'ONECLICK';
            res.matchEvidence = 'Unique Firm; single best-location Office "' + rec.name
                + '"' + (rec.wonOppCount > 0 ? ' (existing customer)' : '') + '.';
        }
        // A website-based match is an exact key hit, but the person's EMAIL domain is new to us -
        // never auto-convert on it; the rep confirms (and the domain can be added as approved).
        if (res.matchedViaWebsite == true && res.confidenceTier == 'ONECLICK') {
            res.confidenceTier = 'REVIEW';
            res.matchEvidence = 'Matched via the lead\'s website ("' + dom2 + '") - the email domain "'
                + dom + '" is new to us. Confirm before converting.';
        }
        return res;
    }

    /**
     * Rank the Offices under one Firm by the same location-first rules, for a
     * given location signal. Used when the SDR picks a Firm from an ambiguous set.
     */
    public static List<CandidateOffice> rankOfficesForFirm(Id firmId, String countryCode, String region) {
        Request r = new Request();
        r.countryCode = countryCode;
        r.region = region;
        List<CandidateOffice> cands = new List<CandidateOffice>();
        for (Account o : [
            SELECT Id, Name, BillingCountryCode, BillingCity, Ultimate_Account__c,
                   No_of_Won_Office_Opportunities__c, Val_of_Won_Office_Opportunities__c,
                   CFY_No_of_Won_Office_Opportunities__c, No_of_Active_Office_Contacts__c
            FROM Account
            WHERE RecordType.DeveloperName = 'Office' AND Ultimate_Account__c = :firmId
        ]) {
            cands.add(toCandidate(o, r));
        }
        cands.sort(new OfficeRanker());
        return cands;
    }

    private static CandidateOffice toCandidate(Account o, Request r) {
        CandidateOffice c = new CandidateOffice();
        c.officeId = o.Id;
        c.name = o.Name;
        c.billingCountryCode = o.BillingCountryCode;
        c.billingCity = o.BillingCity;
        c.wonOppCount = o.No_of_Won_Office_Opportunities__c == null ? 0 : o.No_of_Won_Office_Opportunities__c;
        c.wonOppValue = o.Val_of_Won_Office_Opportunities__c == null ? 0 : o.Val_of_Won_Office_Opportunities__c.doubleValue();
        c.cfyWonOppCount = o.CFY_No_of_Won_Office_Opportunities__c == null ? 0 : o.CFY_No_of_Won_Office_Opportunities__c;
        c.activeContacts = o.No_of_Active_Office_Contacts__c == null ? 0 : o.No_of_Active_Office_Contacts__c;
        c.addressValid = (o.BillingCountryCode != null);   // AddressTools pre-check proxy
        c.locationScore = locationScore(o, r);
        c.evidence = 'loc=' + c.locationScore + ' wonVal=' + c.wonOppValue
            + ' won#=' + c.wonOppCount + (c.addressValid ? '' : ' [ADDRESS INVALID]');
        return c;
    }

    // country match dominates; city match adds a little; AddressTools-invalid is demoted.
    private static Double locationScore(Account o, Request r) {
        Double score = 0;
        if (r.countryCode != null && o.BillingCountryCode != null
            && r.countryCode.equalsIgnoreCase(o.BillingCountryCode)) {
            score += 100;
        }
        if (r.region != null && o.BillingCity != null
            && o.BillingCity.containsIgnoreCase(r.region)) {
            score += 10;
        }
        if (o.BillingCountryCode == null) score -= 50; // demote: would risk an AddressTools rejection
        return score;
    }

    // Sort: location desc, then won value desc, then won count desc, then CFY desc.
    public class OfficeRanker implements Comparator<CandidateOffice> {
        public Integer compare(CandidateOffice a, CandidateOffice b) {
            Integer c = cmp(b.locationScore, a.locationScore);
            if (c != 0) return c;
            c = cmp(b.wonOppValue, a.wonOppValue);
            if (c != 0) return c;
            c = cmp(b.wonOppCount, a.wonOppCount);
            if (c != 0) return c;
            return cmp(b.cfyWonOppCount, a.cfyWonOppCount);
        }
        private Integer cmp(Double x, Double y) {
            if (x == y) return 0;
            return x > y ? 1 : -1;
        }
    }

    // ---- Helpers -----------------------------------------------------------

    // Public reuse for UI controllers: derive the firm domain key from email/website.
    public static String domainKey(String email, String website) {
        Request r = new Request();
        r.email = email;
        r.website = website;
        return extractDomain(r);
    }

    @TestVisible
    static String extractDomain(Request r) {
        Set<String> fm = freeMail();
        String dom = domainFromEmail(r.email);
        if (dom != null && !fm.contains(dom)) return dom;
        // free-mail or no email -> fall back to website host
        String web = hostFromUrl(r.website);
        if (web != null && !fm.contains(web)) return web;
        return null;
    }

    /**
     * The website host as a SECONDARY key - only when a primary (email) key exists, the website
     * host differs from it, and it isn't free-mail. When there is no email key, extractDomain
     * already used the website as the primary, so there is nothing extra to try.
     */
    @TestVisible
    static String secondaryDomain(Request r, String primary) {
        if (primary == null) return null;
        String web = hostFromUrl(r.website);
        if (web == null || web == primary || freeMail().contains(web)) return null;
        return web;
    }

    private static String domainFromEmail(String email) {
        if (String.isBlank(email) || !email.contains('@')) return null;
        return normalize(email.substringAfterLast('@'));
    }

    private static String hostFromUrl(String url) {
        if (String.isBlank(url)) return null;
        String h = url.toLowerCase()
            .replaceFirst('^https?://', '')
            .replaceFirst('^www\\.', '');
        h = h.substringBefore('/').substringBefore('?').trim();
        return String.isBlank(h) ? null : h;
    }

    private static String normalize(String s) {
        return String.isBlank(s) ? null : s.trim().toLowerCase();
    }

    private static void addToDomainMap(Map<String, List<Account>> m, String key, Account a) {
        if (key == null) return;
        if (!m.containsKey(key)) m.put(key, new List<Account>());
        // avoid dupes when both fields carry the same key
        for (Account existing : m.get(key)) { if (existing.Id == a.Id) return; }
        m.get(key).add(a);
    }

    private static Id firmIdOf(Account a) {
        if (a.RecordType != null && a.RecordType.DeveloperName == 'Firm') return a.Id;
        return a.Ultimate_Account__c;   // Office -> its Firm
    }

    private static String firmNameOf(Account a) {
        if (a.RecordType != null && a.RecordType.DeveloperName == 'Firm') return a.Name;
        return a.Ultimate_Account__r != null ? a.Ultimate_Account__r.Name : null;
    }
}
