/**
 * SmartConvertController
 * ----------------------
 * Thin UI controller for the Smart Convert LWC. Assembles the view model from the
 * tested LeadMatchSelectService plus contact-level resolution and existing-customer
 * signals. Keeps the matcher engine stable; all UX shaping lives here.
 */
public with sharing class SmartConvertController {

    // ===== View model =====
    public class View {
        @AuraEnabled public Inbound inbound;
        @AuraEnabled public List<String> scan;
        @AuraEnabled public String conf;          // high | med | none
        @AuraEnabled public String confLabel;
        @AuraEnabled public String tier;          // ONECLICK | REVIEW | GUIDED_CREATE
        @AuraEnabled public Boolean hasFirm;
        @AuraEnabled public Boolean ambiguous;
        @AuraEnabled public Boolean firmNoOffice;
        @AuraEnabled public Firm firm;
        @AuraEnabled public List<Firm> firmOptions;
        @AuraEnabled public List<Office> offices;
        @AuraEnabled public Id recommendedOfficeId;
        @AuraEnabled public Boolean conflict;
        @AuraEnabled public Boolean existingCustomer;
        @AuraEnabled public Boolean knownAccount;  // firm has prior won opps (existing relationship, any brand)
        @AuraEnabled public Boolean familyCustomer; // holds an active SIBLING title in the same brand family
        @AuraEnabled public String brand;         // canonical brand resolved for this lead
        @AuraEnabled public String brandFamily;   // brand family this brand belongs to (e.g. Specialist Platforms)
        @AuraEnabled public String brandStatus;   // customer | prospect | unknown
        @AuraEnabled public String oppMotion;     // New Business | Cross-sell | Upsell | Renewal
        @AuraEnabled public Date renewalDate;     // active term end (set for Upsell/Renewal)
        @AuraEnabled public Banner banner;
        @AuraEnabled public ContactView contact;
        @AuraEnabled public List<ContactOption> contactOptions;
        @AuraEnabled public List<String> dedup;
        @AuraEnabled public List<String> currencies;     // active org currencies (multi-currency)
        @AuraEnabled public String defaultCurrency;      // running user's default currency
        @AuraEnabled public List<OpenOpp> openOpps;      // open opps already on the firm
        @AuraEnabled public Boolean hasOpenBrandOpp;     // an open opp already exists for the lead's brand
        @AuraEnabled public Quality quality;             // lead quality signals (grade/score/email)
        @AuraEnabled public String envLabel;             // org badge: sandbox name or LIVE
    }
    public class Quality {
        @AuraEnabled public String grade;
        @AuraEnabled public Decimal score;
        @AuraEnabled public Decimal radarScore;   // ALM Radar fit score, where applicable
        @AuraEnabled public String emailStatus;
        @AuraEnabled public Boolean emailValid;
        @AuraEnabled public Boolean emailBad;
    }
    public class OpenOpp {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String stage;
        @AuraEnabled public String amount;
        @AuraEnabled public String owner;
        @AuraEnabled public String type;         // Opportunity Type
        @AuraEnabled public String closeDate;    // formatted CloseDate
        @AuraEnabled public String renewalDate;  // formatted Budget_Renewal_Date__c (only when renewal/auto-renewal)
        @AuraEnabled public Boolean isRenewal;   // CPQ or ALM renewal
        @AuraEnabled public Boolean autoRenew;   // ALM auto-renew
        @AuraEnabled public Boolean sameBrand;
        @AuraEnabled public String url;
    }
    public class OwnerView {
        @AuraEnabled public Id firmId;
        @AuraEnabled public String firmOwner;     // Account owner name (informational; not territory here)
        @AuraEnabled public Id firmOwnerId;        // Account owner UserId (for follow-up handoff)
        @AuraEnabled public Boolean youOwn;        // running user owns the firm
        @AuraEnabled public Boolean hasTeam;
        @AuraEnabled public List<TeamMember> team; // account team members across the firm hierarchy
        @AuraEnabled public String relevantName;   // team member whose role covers the lead's brand
        @AuraEnabled public String relevantRole;
        @AuraEnabled public Id relevantUserId;
        @AuraEnabled public String coversDivision; // product Division the brand resolved to
    }
    public class TaskResult {
        @AuraEnabled public Id taskId;
        @AuraEnabled public String url;
        @AuraEnabled public String message;
    }
    public class CommitteeMember {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String title;
        @AuraEnabled public String office;
        @AuraEnabled public String persona;      // inferred buying-committee persona ('' when unclassified)
        @AuraEnabled public Boolean senior;
        @AuraEnabled public String lastActivity;
        @AuraEnabled public String url;
    }
    public class CoverageItem {
        @AuraEnabled public String persona;
        @AuraEnabled public Boolean covered;
    }
    public class CommitteeView {
        @AuraEnabled public Integer count;
        @AuraEnabled public Integer officeCount;
        @AuraEnabled public Integer gaps;
        @AuraEnabled public List<CommitteeMember> members;
        @AuraEnabled public List<CoverageItem> coverage;
    }
    public class TeamMember {
        @AuraEnabled public Id userId;
        @AuraEnabled public String name;
        @AuraEnabled public String role;
        @AuraEnabled public Boolean isYou;
        @AuraEnabled public Boolean covers;   // role covers the lead's brand division
    }
    public class ContactOption {
        @AuraEnabled public Id id;
        @AuraEnabled public Id officeId;       // the office this contact currently sits under
        @AuraEnabled public String name;
        @AuraEnabled public String title;
        @AuraEnabled public String office;
        @AuraEnabled public String lastActivity;
        @AuraEnabled public Boolean sameFirm;
        @AuraEnabled public String tag;
        @AuraEnabled public Boolean recommended;
    }
    public class Inbound {
        @AuraEnabled public String name;
        @AuraEnabled public String title;
        @AuraEnabled public String email;
        @AuraEnabled public String company;
        @AuraEnabled public String country;
        @AuraEnabled public String region;
        @AuraEnabled public String form;
    }
    public class Firm {
        @AuraEnabled public Id id;
        @AuraEnabled public String init;
        @AuraEnabled public String name;
        @AuraEnabled public String meta;
        @AuraEnabled public Id officeId;      // set when a search hit was an OFFICE (id = its parent firm)
        @AuraEnabled public String firmName;  // parent firm name for office hits
    }
    public class Office {
        @AuraEnabled public Id id;
        @AuraEnabled public String nm;
        @AuraEnabled public String meta;
        @AuraEnabled public String sub;       // contacts / recency secondary line
        @AuraEnabled public Integer opps;
        @AuraEnabled public String val;
        @AuraEnabled public Decimal valNum;
        @AuraEnabled public Integer contacts;
        @AuraEnabled public Integer cfyOpps;
        @AuraEnabled public String reco;      // reco | loc | here | ''
        @AuraEnabled public Boolean dim;
        @AuraEnabled public String flag;
        @AuraEnabled public Boolean addressValid;
    }
    public class Banner {
        @AuraEnabled public String cls;       // block | warn | ok | info
        @AuraEnabled public String ic;
        @AuraEnabled public String html;
    }
    public class ContactView {
        @AuraEnabled public String result;    // none | found | jobchange | multiple | create
        @AuraEnabled public String html;
        @AuraEnabled public Id id;
        @AuraEnabled public Id officeId;
    }
    public class ConvertResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public Id accountId;
        @AuraEnabled public Id contactId;
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String message;
        @AuraEnabled public Boolean newAccountCreated;
        @AuraEnabled public Integer duplicatesAvoidedThisWeek;
    }

    // ===== Entry points =====

    @AuraEnabled(cacheable=true)
    public static View getMatch(Id leadId) {
        Lead ld = [
            SELECT Id, FirstName, LastName, Name, Title, Email, Company,
                   Country, CountryCode, City, Website, Status, IsConverted,
                   Lexology_Product__c, ALM_Product_Interest__c,
                   pi__grade__c, pi__score__c, Radar_Fit_Score__c, Validity_Email_Verification_Status__c
            FROM Lead WHERE Id = :leadId LIMIT 1
        ];

        LeadMatchSelectService.Request req = new LeadMatchSelectService.Request();
        req.recordId = ld.Id;
        req.email = ld.Email;
        req.company = ld.Company;
        req.countryCode = ld.CountryCode;
        req.region = ld.City;
        req.website = ld.Website;
        LeadMatchSelectService.Result m =
            LeadMatchSelectService.matchAndSelect(new List<LeadMatchSelectService.Request>{ req })[0];

        View v = new View();
        v.inbound = inboundOf(ld);
        v.tier = m.confidenceTier;
        v.conflict = m.conflict == true;
        v.recommendedOfficeId = m.recommendedOfficeId;

        // Brand-aware sales motion — ONE shared brain (same call the convert path + Pardot door use).
        // Preview assesses the auto-matched firm; convert re-assesses the firm of the office actually
        // chosen (authoritative). Same firm => identical motion; a cross-firm office override re-evaluates.
        v.brand = BrandCustomerStatus.resolveLeadBrand(ld.Lexology_Product__c, ld.ALM_Product_Interest__c, null);
        SalesMotionService.Assessment sm = SalesMotionService.assess(m.resolvedFirmId, v.brand);
        v.brandStatus = sm.brandStatus;
        v.brandFamily = sm.brandFamily;
        v.familyCustomer = sm.familyCustomer;
        v.renewalDate = sm.renewalDate;
        v.knownAccount = sm.knownAccount;
        // brand-level verdict when a brand resolved, else the office won-opp fallback
        v.existingCustomer = (v.brand != null) ? sm.brandCustomer : (m.existingCustomer == true);
        v.oppMotion = sm.motion;
        v.ambiguous = (m.candidateFirmIds != null && m.candidateFirmIds.size() > 1);
        v.hasFirm = (m.resolvedFirmId != null);

        // Confidence
        Boolean viaWeb = (m.matchedViaWebsite == true);
        if (m.confidenceTier == 'ONECLICK') { v.conf = 'high'; v.confLabel = 'Strong match · one firm owns this domain'; }
        else if (m.confidenceTier == 'REVIEW') {
            v.conf = 'med';
            v.confLabel = v.ambiguous ? ('Worth a check · ' + m.candidateFirmIds.size() + ' firms share this domain')
                                      : (viaWeb ? 'Worth a check · matched via the lead\'s website'
                                                : (v.conflict ? 'Firm is clear · we pick the office by location' : 'Worth a quick check before you convert'));
        } else { v.conf = 'none'; v.confLabel = 'No match yet · no existing account'; }

        // Scan trace
        String domain = LeadMatchSelectService.domainKey(ld.Email, ld.Website);
        v.scan = new List<String>{
            'Email domain → <b>' + (domain == null ? '—' : domain) + '</b>',
            'Work or personal email? → <b>' + (domain == null ? 'personal / none' : 'work address') + '</b>',
            v.ambiguous ? ('Matched the domain → <b>' + m.candidateFirmIds.size() + ' firms share it</b>')
                        : (v.hasFirm ? (viaWeb ? 'Email domain new to us → <b>matched via the lead\'s website</b>'
                                               : 'Matched the domain → <b>1 firm</b>')
                                     : 'Matched the domain → <b>no firm found</b>'),
            v.brand != null
                ? (v.existingCustomer ? ('Active ' + v.brand + ' subscription → <b>existing customer / upsell</b>')
                                      : ('No active ' + v.brand + ' subscription → <b>new to ' + v.brand + '</b>'))
                : (v.existingCustomer ? 'Existing relationship → <b>customer</b>'
                                      : (v.hasFirm ? 'Existing relationship → <b>prospect</b>' : 'No confident name + country match'))
        };

        // Contact resolution (email key) + picker options
        resolveContacts(v, ld.Email, m.resolvedFirmId);

        // Firms / offices
        v.firmOptions = new List<Firm>();
        v.offices = new List<Office>();
        if (v.ambiguous) {
            for (Account a : firmRecords(m.candidateFirmIds)) v.firmOptions.add(firmOf(a));
        } else if (v.hasFirm) {
            v.firm = firmOf(firmRecords(new List<Id>{ m.resolvedFirmId })[0]);
            v.offices = mapOffices(m.candidateOffices, m, v.contact);
        }
        // Firm resolved but it has no Office yet -> create the first one under it.
        v.firmNoOffice = (v.hasFirm && v.offices.isEmpty());

        // Existing-customer / dedup
        if (!v.hasFirm && !v.ambiguous) {
            v.dedup = new List<String>{
                'Existing contact on this email? → <b>' + (v.contact.result == 'none' ? 'none' : 'found') + '</b>',
                'Existing account on domain / name? → <b>none</b>',
                'Safe to create → <b>new firm + office</b>'
            };
        }

        // Currency options for an opportunity created at convert (multi-currency orgs)
        v.defaultCurrency = UserInfo.getDefaultCurrency();
        v.currencies = activeCurrencies();

        // Open opportunities already on the firm (avoid creating a duplicate opp)
        populateOpenOpps(v, m.resolvedFirmId);

        // Lead quality signals
        Quality q = new Quality();
        q.grade = ld.pi__grade__c;
        q.score = ld.pi__score__c;
        q.radarScore = ld.Radar_Fit_Score__c;
        q.emailStatus = ld.Validity_Email_Verification_Status__c;
        q.emailValid = (q.emailStatus == 'Valid');
        q.emailBad = (q.emailStatus == 'Invalid');
        v.quality = q;

        v.envLabel = envLabel();
        v.banner = bannerOf(v);
        return v;
    }

    /** Header badge: sandbox name (e.g. KJDEV, FULLUAT) or LIVE in production. */
    private static String envLabel() {
        try {
            if (![SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox) return 'LIVE';
            String host = URL.getOrgDomainUrl().getHost().toLowerCase();
            Integer i = host.indexOf('--');
            if (i > -1) return host.substring(i + 2).substringBefore('.').toUpperCase();
            return 'SANDBOX';
        } catch (Exception e) {
            return '';
        }
    }


    private static void populateOpenOpps(View v, Id firmId) {
        v.openOpps = new List<OpenOpp>();
        v.hasOpenBrandOpp = false;
        if (firmId == null) return;
        Set<Id> acctIds = new Set<Id>{ firmId };
        for (Account a : [SELECT Id FROM Account WHERE Ultimate_Account__c = :firmId]) acctIds.add(a.Id);

        // brands per open opp (via line items) so we can flag same-brand
        Map<Id, Set<String>> oppBrands = new Map<Id, Set<String>>();
        for (OpportunityLineItem oli : [
            SELECT OpportunityId, Product2.Brand__c
            FROM OpportunityLineItem
            WHERE Opportunity.AccountId IN :acctIds AND Opportunity.IsClosed = false AND Product2.Brand__c != null
        ]) {
            if (!oppBrands.containsKey(oli.OpportunityId)) oppBrands.put(oli.OpportunityId, new Set<String>());
            oppBrands.get(oli.OpportunityId).add(oli.Product2.Brand__c);
        }

        for (Opportunity o : [
            SELECT Id, Name, StageName, Amount, Type, CloseDate, Owner.Name,
                   Budget_Renewal_Date__c, SBQQ__Renewal__c, isRenewal__c, ALM_Auto_Renew__c
            FROM Opportunity
            WHERE AccountId IN :acctIds AND IsClosed = false
            ORDER BY CreatedDate DESC LIMIT 10
        ]) {
            OpenOpp oo = new OpenOpp();
            oo.id = o.Id;
            oo.name = o.Name;
            oo.stage = o.StageName;
            oo.amount = o.Amount == null ? '' : money(o.Amount);
            oo.owner = o.Owner != null ? o.Owner.Name : '';
            oo.type = o.Type;
            oo.closeDate = fmtDate(o.CloseDate);
            // Renewal vs auto-renewal lives in the Type picklist in this org (the SBQQ__/ALM_
            // booleans are sparsely/inconsistently set); use Type first, flags as a fallback.
            String ty = o.Type == null ? '' : o.Type;
            oo.autoRenew = (ty == 'Auto-Renewal' || ty == 'Auto-Repeat Business' || o.ALM_Auto_Renew__c == true);
            oo.isRenewal = (oo.autoRenew || ty == 'Renewal' || ty == 'Repeat Business'
                            || o.SBQQ__Renewal__c == true || o.isRenewal__c == true);
            // Budget renewal date is only meaningful on a renewal / auto-renewal opp
            oo.renewalDate = (oo.isRenewal || oo.autoRenew) ? fmtDate(o.Budget_Renewal_Date__c) : '';
            oo.url = '/lightning/r/Opportunity/' + o.Id + '/view';
            oo.sameBrand = (v.brand != null && oppBrands.containsKey(o.Id) && oppBrands.get(o.Id).contains(v.brand));
            if (oo.sameBrand) v.hasOpenBrandOpp = true;
            v.openOpps.add(oo);
        }
    }

    private static List<String> activeCurrencies() {
        List<String> codes = new List<String>();
        if (!UserInfo.isMultiCurrencyOrganization()) return codes;
        for (SObject ct : Database.query('SELECT IsoCode FROM CurrencyType WHERE IsActive = true ORDER BY IsoCode')) {
            codes.add((String) ct.get('IsoCode'));
        }
        return codes;
    }

    /**
     * Manual override: free-text search by FIRM or OFFICE name (escape hatch when auto-match is
     * wrong/empty). Reps often know the local office name, which can differ from the legal firm
     * name — an Office hit resolves to its parent Firm and carries officeId so the picker can
     * pre-select that office.
     */
    @AuraEnabled(cacheable=true)
    public static List<Firm> searchFirms(String term) {
        List<Firm> out = new List<Firm>();
        if (String.isBlank(term) || term.trim().length() < 2) return out;
        String likeTerm = '%' + term.trim() + '%';
        for (Account a : [
            SELECT Id, Name, Website, Match_Domain__c, Ultimate_Account_Name__c,
                   No_of_Offices__c, No_of_Office_Contacts__c, No_of_Won_Office_Opportunities__c,
                   (SELECT BillingCity, BillingCountryCode FROM Accounts__r
                    WHERE RecordType.DeveloperName = 'Office' AND BillingCity != null LIMIT 3)
            FROM Account
            WHERE RecordType.DeveloperName = 'Firm' AND Name LIKE :likeTerm
            ORDER BY Name LIMIT 15
        ]) {
            out.add(firmOf(a));
        }
        for (Account a : [
            SELECT Id, Name, BillingCity, BillingCountryCode,
                   Ultimate_Account__c, Ultimate_Account__r.Name
            FROM Account
            WHERE RecordType.DeveloperName = 'Office' AND Ultimate_Account__c != null
              AND Name LIKE :likeTerm
            ORDER BY Name LIMIT 15
        ]) {
            Firm f = new Firm();
            f.id = a.Ultimate_Account__c;                 // placement is always the parent firm
            f.officeId = a.Id;                            // pre-select this office in the picker
            f.name = a.Name;
            f.firmName = a.Ultimate_Account__r != null ? a.Ultimate_Account__r.Name : null;
            String loc = (a.BillingCity == null ? '' : a.BillingCity)
                + (a.BillingCountryCode == null ? '' : (a.BillingCity == null ? '' : ', ') + a.BillingCountryCode);
            f.meta = 'Office of ' + f.firmName + (String.isBlank(loc) ? '' : ' · ' + loc);
            f.init = f.name.substring(0, 1).toUpperCase();
            out.add(f);
        }
        return out;
    }

    @AuraEnabled(cacheable=true)
    public static List<Office> getOfficesForFirm(Id leadId, Id firmId) {
        Lead ld = [SELECT CountryCode, City, Email FROM Lead WHERE Id = :leadId LIMIT 1];
        List<LeadMatchSelectService.CandidateOffice> cands =
            LeadMatchSelectService.rankOfficesForFirm(firmId, ld.CountryCode, ld.City);
        // Build a minimal Result-like context for reco tagging: first = recommended.
        LeadMatchSelectService.Result ctx = new LeadMatchSelectService.Result();
        ctx.candidateOffices = cands;
        ctx.recommendedOfficeId = cands.isEmpty() ? null : cands[0].officeId;
        ctx.conflict = false;
        View tmp = new View();
        resolveContacts(tmp, ld.Email, firmId);
        return mapOffices(cands, ctx, tmp.contact);
    }

    /**
     * Account team + owner for the resolved firm. Ownership is NOT territory at Centellic (most
     * accounts share one owner), so the useful signal is the Account Team — pulled across the whole
     * firm hierarchy (firm + offices) and matched to the lead's brand via product Division so the UI
     * can point the rep at the CSM who actually covers this product (Law.com CSM / PI CSM / E&I CSM).
     * Runs WITHOUT sharing (see OwnershipReader) so team visibility doesn't depend on record access.
     */
    @AuraEnabled(cacheable=true)
    public static OwnerView getOwnership(Id firmId, String brand) {
        OwnerView ov = new OwnerView();
        ov.team = new List<TeamMember>();
        ov.hasTeam = false;
        ov.youOwn = false;
        ov.firmId = firmId;
        if (firmId == null) return ov;
        try {
            return new OwnershipReader().read(firmId, brand);
        } catch (Exception e) {
            return ov;   // best-effort; panel simply shows nothing
        }
    }

    /** Modal Division of the brand's subscription products (falls back to all products). */
    @TestVisible
    static String brandDivision(String brand) {
        if (String.isBlank(brand)) return null;
        String grp = BrandCustomerStatus.matchGroupFor(brand);
        List<AggregateResult> rows = (grp != null)
            ? [SELECT Division__c d, COUNT(Id) c FROM Product2 WHERE Product_Group__c = :grp
               AND Division__c != null GROUP BY Division__c ORDER BY COUNT(Id) DESC LIMIT 1]
            : [SELECT Division__c d, COUNT(Id) c FROM Product2 WHERE Brand__c = :brand
               AND Product_Group__c LIKE 'Subs%' AND Division__c != null
               GROUP BY Division__c ORDER BY COUNT(Id) DESC LIMIT 1];
        if (rows.isEmpty() && grp == null) {
            rows = [SELECT Division__c d, COUNT(Id) c FROM Product2 WHERE Brand__c = :brand
                    AND Division__c != null GROUP BY Division__c ORDER BY COUNT(Id) DESC LIMIT 1];
        }
        return rows.isEmpty() ? null : (String) rows[0].get('d');
    }

    /** Which team-member role keyword covers a product Division (org CS structure). */
    @TestVisible
    static String roleKeywordForDivision(String division) {
        if (division == 'ALM') return 'law.com';
        if (division == 'Practice Intelligence') return 'pi';
        if (division == 'Events' || division == 'Market Intelligence') return 'e&i';
        return null;
    }

    private without sharing class OwnershipReader {
        OwnerView read(Id firmId, String brand) {
            OwnerView ov = new OwnerView();
            ov.firmId = firmId;
            ov.team = new List<TeamMember>();
            ov.youOwn = false;
            Id me = UserInfo.getUserId();
            for (Account a : [SELECT OwnerId, Owner.Name FROM Account WHERE Id = :firmId LIMIT 1]) {
                ov.firmOwner = a.Owner != null ? a.Owner.Name : null;
                ov.firmOwnerId = a.OwnerId;
                ov.youOwn = (a.OwnerId == me);
            }
            // Team across the firm hierarchy (members are often on the offices, not the firm record)
            Set<Id> acctIds = new Set<Id>{ firmId };
            for (Account a : [SELECT Id FROM Account WHERE Ultimate_Account__c = :firmId]) acctIds.add(a.Id);
            String division = brandDivision(brand);
            String keyword = roleKeywordForDivision(division);
            ov.coversDivision = division;
            Set<Id> seenUsers = new Set<Id>();
            for (AccountTeamMember m : [
                SELECT UserId, User.Name, TeamMemberRole
                FROM AccountTeamMember WHERE AccountId IN :acctIds
                ORDER BY TeamMemberRole NULLS LAST, User.Name
            ]) {
                if (seenUsers.contains(m.UserId)) continue;
                seenUsers.add(m.UserId);
                TeamMember tm = new TeamMember();
                tm.userId = m.UserId;
                tm.name = m.User != null ? m.User.Name : null;
                tm.role = String.isBlank(m.TeamMemberRole) ? '—' : m.TeamMemberRole;
                tm.isYou = (m.UserId == me);
                tm.covers = (keyword != null && tm.role.toLowerCase().contains(keyword));
                if (tm.covers && ov.relevantUserId == null) {
                    ov.relevantUserId = tm.userId;
                    ov.relevantName = tm.name;
                    ov.relevantRole = tm.role;
                }
                ov.team.add(tm);
            }
            ov.hasTeam = !ov.team.isEmpty();
            return ov;
        }
    }

    // The ideal Lexology Pro buying committee — what "good coverage" looks like at a firm.
    static final List<String> PRO_COMMITTEE =
        new List<String>{ 'Knowledge / PSL', 'Library / Research', 'L&D', 'Practice leadership' };

    /**
     * Buying-committee view for the resolved firm: existing contacts across its offices, tagged with an
     * inferred Pro persona, plus a coverage read (which key personas are present vs. a gap) so the SDR
     * can multi-thread instead of converting a single lead in isolation.
     */
    @AuraEnabled(cacheable=true)
    public static CommitteeView getBuyingCommittee(Id firmId) {
        CommitteeView cv = new CommitteeView();
        cv.members = new List<CommitteeMember>();
        cv.coverage = new List<CoverageItem>();
        cv.count = 0; cv.officeCount = 0; cv.gaps = 0;
        if (firmId == null) return cv;

        Set<Id> acctIds = new Set<Id>{ firmId };
        for (Account a : [SELECT Id FROM Account WHERE Ultimate_Account__c = :firmId]) acctIds.add(a.Id);

        Set<Id> offices = new Set<Id>();
        Set<String> present = new Set<String>();
        List<CommitteeMember> seniors = new List<CommitteeMember>();
        List<CommitteeMember> others = new List<CommitteeMember>();
        for (Contact c : [
            SELECT Id, Name, Title, AccountId, Account.Name, LastActivityDate
            FROM Contact WHERE AccountId IN :acctIds
            ORDER BY LastActivityDate DESC NULLS LAST
            LIMIT 30
        ]) {
            CommitteeMember m = new CommitteeMember();
            m.id = c.Id;
            m.name = c.Name;
            m.title = c.Title;
            m.office = c.Account != null ? c.Account.Name : null;
            m.persona = inferPersona(c.Title);
            m.senior = isSenior(c.Title);
            m.lastActivity = fmtDate(c.LastActivityDate);
            m.url = '/lightning/r/Contact/' + c.Id + '/view';
            if (m.senior) seniors.add(m); else others.add(m);
            if (c.AccountId != null) offices.add(c.AccountId);
            if (String.isNotBlank(m.persona)) present.add(m.persona);
        }
        cv.members.addAll(seniors);   // seniors first, each group already recency-ordered
        cv.members.addAll(others);
        cv.count = cv.members.size();
        cv.officeCount = offices.size();
        for (String p : PRO_COMMITTEE) {
            CoverageItem ci = new CoverageItem();
            ci.persona = p;
            ci.covered = present.contains(p);
            if (!ci.covered) cv.gaps++;
            cv.coverage.add(ci);
        }
        return cv;
    }

    @TestVisible
    static String inferPersona(String title) {
        if (String.isBlank(title)) return '';
        String t = title.toLowerCase();
        if (containsAny(t, new List<String>{ 'knowledge', 'psl', 'professional support', 'know-how', 'knowhow', 'know how' })) return 'Knowledge / PSL';
        if (containsAny(t, new List<String>{ 'library', 'librarian', 'information officer', 'information manager', 'information services', 'research' })) return 'Library / Research';
        if (containsAny(t, new List<String>{ 'learning', 'l&d', 'training', 'talent development' })) return 'L&D';
        if (containsAny(t, new List<String>{ 'partner', 'head of', 'practice', 'managing', 'chair', 'general counsel', 'director', 'chief' })) return 'Practice leadership';
        return '';
    }

    @TestVisible
    static Boolean isSenior(String title) {
        if (String.isBlank(title)) return false;
        return containsAny(title.toLowerCase(), new List<String>{
            'partner', 'head', 'chief', 'director', 'general counsel', 'gc', 'managing',
            'chair', 'president', 'vp', 'vice president', 'coo', 'ceo', 'cio' });
    }

    private static Boolean containsAny(String hay, List<String> needles) {
        for (String n : needles) { if (hay.contains(n)) return true; }
        return false;
    }

    /**
     * Post-convert next action: create a follow-up Task on the converted contact + opportunity so a
     * converted lead never dies untouched. Assigned to the running user by default, or handed to the
     * account owner. Uses the caller's default Task record type (portable across orgs).
     */
    @AuraEnabled
    public static TaskResult createFollowUpTask(Id opportunityId, Id contactId, Id accountId,
            String subject, Integer dueInDays, Id assignToUserId, String note, String taskType) {
        TaskResult tr = new TaskResult();
        try {
            Integer days = (dueInDays == null || dueInDays < 0) ? 2 : dueInDays;
            Task t = new Task();
            t.Subject = String.isBlank(subject) ? 'Follow up' : subject;
            if (contactId != null) t.WhoId = contactId;
            t.WhatId = (opportunityId != null) ? opportunityId : accountId;   // opp preferred, else account
            t.OwnerId = (assignToUserId != null) ? assignToUserId : UserInfo.getUserId();
            t.ActivityDate = Date.today().addDays(days);
            t.Status = 'Open';
            t.Priority = 'Normal';
            if (String.isNotBlank(taskType)) t.Type = taskType;
            if (String.isNotBlank(note)) t.Description = note;
            insert t;
            tr.taskId = t.Id;
            tr.url = '/lightning/r/Task/' + t.Id + '/view';
        } catch (Exception e) {
            tr.message = e.getMessage();
        }
        return tr;
    }

    @AuraEnabled
    public static ConvertResult convert(Id leadId, Id officeId, Id contactId, Boolean createOpportunity,
                                        String matchConfidence, Boolean newAccountCreated, String currencyIsoCode,
                                        Id recommendedOfficeId, Boolean manualSearchUsed, String createReason,
                                        String disqualifyReason) {
        // Capture the decision: did the rep override the recommended office?
        Boolean overrode = (recommendedOfficeId != null && officeId != null && officeId != recommendedOfficeId);
        // Classify the sales motion (new / cross-sell / upsell / renewal) for naming + telemetry.
        MotionResult mo = resolveMotion(leadId, officeId);
        // Stamp telemetry BEFORE convert (normal Lead update; the KPI query filters on IsConverted).
        stampTelemetry(leadId, matchConfidence, newAccountCreated, recommendedOfficeId, overrode, manualSearchUsed,
            createReason, disqualifyReason, mo.motion);

        LeadConvertInvocable.Request r = new LeadConvertInvocable.Request();
        r.leadId = leadId;
        r.accountId = officeId;
        r.contactId = contactId;
        r.createOpportunity = createOpportunity == true;
        LeadConvertInvocable.Result lr =
            LeadConvertInvocable.convert(new List<LeadConvertInvocable.Request>{ r })[0];
        ConvertResult out = new ConvertResult();
        out.success = lr.success;
        out.accountId = lr.accountId;
        out.contactId = lr.contactId;
        out.opportunityId = lr.opportunityId;
        out.message = lr.message;
        out.newAccountCreated = newAccountCreated == true;
        if (out.success) {
            out.duplicatesAvoidedThisWeek = countDuplicatesAvoidedThisWeek();
            if (out.opportunityId != null) {
                prefillOpportunity(out.opportunityId, leadId, currencyIsoCode, mo);
                stampContactRole(out.opportunityId, out.contactId);
            }
        }
        return out;
    }

    // ===== Sales-motion (delegates to the shared SalesMotionService — one brain for both doors) =====
    public class MotionResult {
        public String motion;     // New Business | Cross-sell | Upsell | Renewal
        public Date renewalDate;  // active term end (Upsell/Renewal only)
    }

    /** Resolve the motion at convert time from the actual target office + the lead's brand. */
    private static MotionResult resolveMotion(Id leadId, Id officeId) {
        MotionResult mo = new MotionResult();
        mo.motion = 'New Business';
        if (officeId == null) return mo;
        try {
            Lead l = [SELECT Lexology_Product__c, ALM_Product_Interest__c FROM Lead WHERE Id = :leadId LIMIT 1];
            Id firmId = officeId;
            for (Account o : [SELECT Ultimate_Account__c FROM Account WHERE Id = :officeId LIMIT 1]) {
                if (o.Ultimate_Account__c != null) firmId = o.Ultimate_Account__c;
            }
            SalesMotionService.Assessment a =
                SalesMotionService.assessFromSource(firmId, l.Lexology_Product__c, l.ALM_Product_Interest__c, null);
            mo.motion = a.motion;
            mo.renewalDate = a.renewalDate;
        } catch (Exception e) {
            // best-effort; default to New Business
        }
        return mo;
    }

    /** Map a motion to the org's Opportunity Type picklist. */
    private static String oppTypeFor(String motion) {
        if (motion == 'Renewal') return 'Renewal';
        if (motion == 'Upsell') return 'Upsell';
        if (motion == 'Cross-sell') return 'Repeat Business';
        return 'New Business';
    }

    /** Pre-fill the freshly-converted opportunity: motion-aware name + Type, brand, source, currency. Best-effort. */
    private static void prefillOpportunity(Id oppId, Id leadId, String currencyIsoCode, MotionResult mo) {
        try {
            Lead l = [SELECT Company, LeadSource, Lexology_Product__c, ALM_Product_Interest__c
                      FROM Lead WHERE Id = :leadId LIMIT 1];
            String brand = BrandCustomerStatus.resolveLeadBrand(l.Lexology_Product__c, l.ALM_Product_Interest__c, null);
            String co = String.isBlank(l.Company) ? 'New Business' : l.Company;
            String motion = (mo != null && String.isNotBlank(mo.motion)) ? mo.motion : 'New Business';
            Opportunity opp = new Opportunity(Id = oppId);
            opp.Name = co + (brand != null ? ' - ' + brand : '') + ' - ' + motion;
            opp.Description = 'Inbound lead' + (brand != null ? ' interested in ' + brand : '')
                + ' — ' + motion + '. Converted via Smart Convert.';
            opp.Type = oppTypeFor(motion);
            if (String.isNotBlank(brand)) opp.Product_list__c = brand;
            if (String.isNotBlank(l.LeadSource)) opp.LeadSource = l.LeadSource;
            // Renewal: aim the close date at the current term end so it lands on the renewal forecast.
            if (motion == 'Renewal' && mo != null && mo.renewalDate != null && mo.renewalDate >= Date.today()) {
                opp.CloseDate = mo.renewalDate;
            }
            if (String.isNotBlank(currencyIsoCode) && UserInfo.isMultiCurrencyOrganization()) {
                opp.put('CurrencyIsoCode', currencyIsoCode);
            }
            update opp;
        } catch (Exception e) {
            // best-effort; opp keeps the platform-default values
        }
    }

    /**
     * Stamp the opportunity contact role as "Decision Maker" for the converted contact.
     * Lead-convert creates the primary OCR with a blank Role; we fill it in. Non-destructive:
     * only sets the role when it's blank, so a role assigned by CPQ/other automation is never
     * overwritten. Best-effort — never blocks the convert.
     */
    private static void stampContactRole(Id oppId, Id contactId) {
        try {
            List<OpportunityContactRole> ocrs = [
                SELECT Id, Role, IsPrimary, ContactId
                FROM OpportunityContactRole WHERE OpportunityId = :oppId
            ];
            List<OpportunityContactRole> toUpdate = new List<OpportunityContactRole>();
            for (OpportunityContactRole ocr : ocrs) {
                Boolean isTarget = (contactId != null && ocr.ContactId == contactId) || ocr.IsPrimary == true;
                if (isTarget && String.isBlank(ocr.Role)) {
                    ocr.Role = 'Decision Maker';
                    toUpdate.add(ocr);
                }
            }
            if (!toUpdate.isEmpty()) update toUpdate;
        } catch (Exception e) {
            // best-effort; role stays as the platform default
        }
    }

    private static void stampTelemetry(Id leadId, String matchConfidence, Boolean newAccountCreated,
            Id recommendedOfficeId, Boolean overrode, Boolean manualSearchUsed, String createReason,
            String disqualifyReason, String oppMotion) {
        try {
            update new Lead(Id = leadId,
                Match_Confidence__c = matchConfidence,
                Conversion_Source__c = 'Smart Convert',
                New_Account_Created__c = newAccountCreated == true,
                Recommended_Office__c = recommendedOfficeId,
                Overrode_Recommendation__c = overrode == true,
                Manual_Search_Used__c = manualSearchUsed == true,
                Create_Reason__c = createReason,
                Disqualify_Reason__c = disqualifyReason,
                Disqualified_At_Convert__c = String.isNotBlank(disqualifyReason),
                Opportunity_Motion__c = oppMotion);
        } catch (Exception e) {
            // telemetry is best-effort; never block the convert
        }
    }

    private static Integer countDuplicatesAvoidedThisWeek() {
        return [
            SELECT COUNT() FROM Lead
            WHERE IsConverted = true AND Conversion_Source__c = 'Smart Convert'
              AND New_Account_Created__c = false AND ConvertedDate = THIS_WEEK
        ];
    }

    /**
     * Phase 1 of the guided-create path: build the new Firm and/or first Office in its OWN
     * transaction. The account inserts fire the managed dedup/enrichment triggers plus our
     * Account flows; sharing one governor budget with the convert (and the Opportunity master
     * flow) hit "Too many SOQL queries: 101" in production. The LWC calls convert() as a second
     * transaction. If that second call fails, nothing is lost: the new firm's match key is
     * already stamped, so a Restart re-matches it and the retry converges on the same account
     * instead of creating a duplicate.
     */
    @AuraEnabled
    public static ConvertResult createAccountShell(Id leadId, Id firmId) {
        ConvertResult out = new ConvertResult();
        try {
            out.accountId = buildShell(leadId, firmId);
            out.success = true;
            out.newAccountCreated = true;
        } catch (Exception e) {
            out.success = false;
            out.message = 'Create blocked: ' + e.getMessage();
        }
        return out;
    }

    /** Create the Firm (when firmId is null) + first Office from the lead; returns the Office id. */
    private static Id buildShell(Id leadId, Id firmId) {
        Lead ld = [SELECT Company, Country, CountryCode, City, Street, Email, Website FROM Lead WHERE Id = :leadId LIMIT 1];
        String firmName;
        if (firmId == null) {
            Id firmRt = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Firm').getRecordTypeId();
            firmName = String.isBlank(ld.Company) ? 'New Firm' : ld.Company;
            // Firm is the rollup parent — no address; the address belongs on the Office.
            // Originated_From_Lead__c satisfies the org's Can_Create_Account_only_via_Lead rule —
            // these accounts genuinely originate from a lead (dedup-checked, Data Team notified).
            Account firm = new Account(Name = firmName, RecordTypeId = firmRt,
                Originated_From_Lead__c = true,
                Match_Domain__c = LeadMatchSelectService.domainKey(ld.Email, ld.Website));
            insert firm;
            firmId = firm.Id;
        } else {
            firmName = [SELECT Name FROM Account WHERE Id = :firmId LIMIT 1].Name;
        }
        Account office = buildOffice(firmId, firmName, ld);
        insert office;
        return office.Id;
    }

    /** Guided-create in one transaction (kept for API stability; the LWC runs the two-phase path). */
    @AuraEnabled
    public static ConvertResult createAndConvert(Id leadId, Boolean createOpportunity, String matchConfidence,
            String currencyIsoCode, Boolean manualSearchUsed, String createReason, String disqualifyReason) {
        try {
            Id officeId = buildShell(leadId, null);
            return convert(leadId, officeId, null, createOpportunity, matchConfidence, true, currencyIsoCode,
                null, manualSearchUsed, createReason, disqualifyReason);
        } catch (Exception e) {
            ConvertResult out = new ConvertResult();
            out.success = false;
            out.message = 'Create blocked: ' + e.getMessage();
            return out;
        }
    }

    /** Firm exists but has no Office: create the first Office UNDER the existing Firm, then convert. */
    @AuraEnabled
    public static ConvertResult createOfficeUnderFirm(Id leadId, Id firmId, Boolean createOpportunity,
            String matchConfidence, String currencyIsoCode, Boolean manualSearchUsed, String createReason,
            String disqualifyReason) {
        try {
            Id officeId = buildShell(leadId, firmId);
            return convert(leadId, officeId, null, createOpportunity, matchConfidence, true, currencyIsoCode,
                null, manualSearchUsed, createReason, disqualifyReason);
        } catch (Exception e) {
            ConvertResult out = new ConvertResult();
            out.success = false;
            out.message = 'Create blocked: ' + e.getMessage();
            return out;
        }
    }

    private static Account buildOffice(Id firmId, String firmName, Lead ld) {
        Id officeRt = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Office').getRecordTypeId();
        String loc = String.isBlank(ld.City) ? (String.isBlank(ld.Country) ? 'HQ' : ld.Country) : ld.City;
        return new Account(Name = firmName + ' — ' + loc, RecordTypeId = officeRt,
            Ultimate_Account__c = firmId, Originated_From_Lead__c = true,
            BillingCountryCode = ld.CountryCode, BillingCity = ld.City, BillingStreet = ld.Street);
    }

    // ===== Helpers =====

    private static Inbound inboundOf(Lead ld) {
        Inbound i = new Inbound();
        i.name = (ld.Name != null ? ld.Name : ((ld.FirstName == null ? '' : ld.FirstName + ' ') + ld.LastName));
        i.title = ld.Title;
        i.email = ld.Email;
        i.company = ld.Company;
        i.country = ld.Country;
        i.region = ld.City;
        i.form = ld.Status;
        return i;
    }

    private static List<Account> firmRecords(List<Id> ids) {
        return [
            SELECT Id, Name, Website, Match_Domain__c, Ultimate_Account_Name__c,
                   No_of_Offices__c, No_of_Office_Contacts__c, No_of_Won_Office_Opportunities__c,
                   (SELECT BillingCity, BillingCountryCode FROM Accounts__r
                    WHERE RecordType.DeveloperName = 'Office' AND BillingCity != null LIMIT 3)
            FROM Account WHERE Id IN :ids
        ];
    }

    private static Firm firmOf(Account a) {
        Firm f = new Firm();
        f.id = a.Id;
        f.name = a.Name;
        f.init = (a.Name != null && a.Name.length() > 0) ? a.Name.substring(0, 1).toUpperCase() : '?';
        List<String> bits = new List<String>();
        String dom = (a.Match_Domain__c != null) ? a.Match_Domain__c : LeadMatchSelectService.domainKey(null, a.Website);
        if (String.isNotBlank(dom)) bits.add(dom);                                  // the website/domain key
        // Office locations - the fastest way to tell similarly named firms apart (UAT feedback)
        List<String> cities = new List<String>();
        if (a.getSObjects('Accounts__r') != null) {
            for (SObject o : a.getSObjects('Accounts__r')) {
                String city = (String) o.get('BillingCity');
                String cc = (String) o.get('BillingCountryCode');
                if (String.isNotBlank(city) && cities.size() < 2) {
                    cities.add(city + (String.isNotBlank(cc) ? ' ' + cc : ''));
                }
            }
        }
        if (!cities.isEmpty()) bits.add(String.join(cities, ' / '));
        if (a.No_of_Offices__c != null) bits.add(a.No_of_Offices__c.intValue() + ' offices');
        if (a.No_of_Office_Contacts__c != null) bits.add(a.No_of_Office_Contacts__c.intValue() + ' contacts');
        if (a.No_of_Won_Office_Opportunities__c != null && a.No_of_Won_Office_Opportunities__c > 0) {
            bits.add(a.No_of_Won_Office_Opportunities__c.intValue() + ' won opps');
        }
        if (bits.isEmpty()) bits.add('Firm');
        f.meta = String.join(bits, ' · ');
        return f;
    }

    private static List<Office> mapOffices(List<LeadMatchSelectService.CandidateOffice> cands,
                                           LeadMatchSelectService.Result m, ContactView cv) {
        List<Office> out = new List<Office>();
        if (cands == null || cands.isEmpty()) return out;
        // The office cards read the rh2-maintained rollup fields. When they're unpopulated for the
        // whole candidate set (FULLUAT has none; rh2 staleness can hit prod too), compute the numbers
        // live for this one firm instead of showing zeros. Interactive path only — bulk stays on rollups.
        Boolean rollupsEmpty = true;
        Set<Id> officeIds = new Set<Id>();
        for (LeadMatchSelectService.CandidateOffice c : cands) {
            officeIds.add(c.officeId);
            if ((c.wonOppCount != null && c.wonOppCount > 0)
                || (c.wonOppValue != null && c.wonOppValue > 0)
                || (c.activeContacts != null && c.activeContacts > 0)) rollupsEmpty = false;
        }
        Map<Id, Integer> liveWon = new Map<Id, Integer>();
        Map<Id, Decimal> liveVal = new Map<Id, Decimal>();
        Map<Id, Integer> liveCfy = new Map<Id, Integer>();
        Map<Id, Integer> liveContacts = new Map<Id, Integer>();
        if (rollupsEmpty) {
            try {
                for (AggregateResult ar : [SELECT AccountId a, COUNT(Id) c, SUM(Amount) s FROM Opportunity
                                           WHERE AccountId IN :officeIds AND IsWon = true GROUP BY AccountId]) {
                    liveWon.put((Id) ar.get('a'), (Integer) ar.get('c'));
                    liveVal.put((Id) ar.get('a'), (Decimal) ar.get('s'));
                }
                for (AggregateResult ar : [SELECT AccountId a, COUNT(Id) c FROM Opportunity
                                           WHERE AccountId IN :officeIds AND IsWon = true
                                           AND CloseDate = THIS_FISCAL_YEAR GROUP BY AccountId]) {
                    liveCfy.put((Id) ar.get('a'), (Integer) ar.get('c'));
                }
                for (AggregateResult ar : [SELECT AccountId a, COUNT(Id) c FROM Contact
                                           WHERE AccountId IN :officeIds GROUP BY AccountId]) {
                    liveContacts.put((Id) ar.get('a'), (Integer) ar.get('c'));
                }
            } catch (Exception e) {
                rollupsEmpty = false;   // best-effort; fall back to the (zero) rollups
            }
        }
        Decimal recVal = cands[0].wonOppValue == null ? 0 : cands[0].wonOppValue;
        Double recLoc = cands[0].locationScore == null ? 0 : cands[0].locationScore;
        for (LeadMatchSelectService.CandidateOffice c : cands) {
            Office o = new Office();
            o.id = c.officeId;
            o.nm = c.name;
            String loc = (c.billingCity == null ? '' : c.billingCity)
                + (c.billingCountryCode == null ? '' : ', ' + c.billingCountryCode);
            o.meta = (c.locationScore != null && c.locationScore >= 100) ? (loc + ' · matches lead location') : loc;
            if (rollupsEmpty) {
                o.opps = liveWon.containsKey(c.officeId) ? liveWon.get(c.officeId) : 0;
                o.valNum = liveVal.containsKey(c.officeId) && liveVal.get(c.officeId) != null ? liveVal.get(c.officeId) : 0;
                o.contacts = liveContacts.containsKey(c.officeId) ? liveContacts.get(c.officeId) : 0;
                o.cfyOpps = liveCfy.containsKey(c.officeId) ? liveCfy.get(c.officeId) : 0;
            } else {
                o.opps = c.wonOppCount == null ? 0 : c.wonOppCount.intValue();
                o.valNum = c.wonOppValue == null ? 0 : c.wonOppValue;
                o.contacts = c.activeContacts == null ? 0 : c.activeContacts.intValue();
                o.cfyOpps = c.cfyWonOppCount == null ? 0 : c.cfyWonOppCount.intValue();
            }
            o.val = money(o.valNum);
            o.addressValid = c.addressValid == true;
            o.sub = o.contacts + (rollupsEmpty ? ' contacts · ' : ' active contacts · ')
                + o.cfyOpps + ' opps this FY'
                + (o.opps > 0 ? '' : ' · no won deals yet');
            // reco tagging
            if (cv != null && cv.officeId == c.officeId) {
                o.reco = 'here';
            } else if (c.officeId == m.recommendedOfficeId) {
                o.reco = (m.conflict == true) ? 'loc' : 'reco';
            } else {
                o.reco = '';
            }
            // conflict de-emphasis + flag
            if (m.conflict == true && c.officeId != m.recommendedOfficeId
                && (c.locationScore == null ? 0 : c.locationScore) < recLoc) {
                o.dim = true;
                if (o.valNum > recVal) o.flag = '⚠ more opps, but wrong location';
            } else {
                o.dim = false;
            }
            if (!o.addressValid) o.flag = '⚠ address looks invalid — may be rejected on save';
            out.add(o);
        }
        return out;
    }

    private static void resolveContacts(View v, String email, Id firmId) {
        ContactView cv = new ContactView();
        cv.result = 'none';
        v.contactOptions = new List<ContactOption>();
        if (String.isBlank(email)) {
            cv.html = 'No email on the lead — we can only check for an existing contact by name.';
            v.contact = cv;
            return;
        }
        List<Contact> matches = [
            SELECT Id, Name, Title, AccountId, Account.Name, Account.Ultimate_Account__c, LastActivityDate
            FROM Contact WHERE Email = :email ORDER BY LastActivityDate DESC NULLS LAST LIMIT 50
        ];
        if (matches.isEmpty()) {
            cv.html = 'No existing contact found for <b>' + email + '</b> — we\'ll create a new one.';
            v.contact = cv;
            return;
        }

        // Build selectable options (with details) + decide the recommendation.
        Integer sameFirmCount = 0;
        ContactOption firstSameFirm = null;
        Id sameFirmOfficeId = null;
        for (Contact c : matches) {
            ContactOption o = new ContactOption();
            o.id = c.Id;
            o.officeId = c.AccountId;
            o.name = c.Name;
            o.title = String.isBlank(c.Title) ? '—' : c.Title;
            o.office = (c.Account != null) ? c.Account.Name : 'No account';
            o.lastActivity = (c.LastActivityDate != null) ? c.LastActivityDate.format() : 'no recent activity';
            o.sameFirm = (firmId != null && c.Account != null && c.Account.Ultimate_Account__c == firmId);
            o.tag = o.sameFirm ? 'same firm' : 'different firm — may have changed jobs';
            if (o.sameFirm) {
                sameFirmCount++;
                if (firstSameFirm == null) { firstSameFirm = o; sameFirmOfficeId = c.AccountId; }
            }
            v.contactOptions.add(o);
        }
        // Recommend the most-recent same-firm contact; if none, recommend "create new".
        if (firstSameFirm != null) firstSameFirm.recommended = true;

        if (sameFirmCount == 1) {
            cv.result = 'found'; cv.id = firstSameFirm.id; cv.officeId = sameFirmOfficeId;
            cv.html = '<b>' + email + '</b> already belongs to a contact at this firm — we\'ll <b>link</b> the enquiry to them rather than create a duplicate. Confirm the person below.';
        } else if (sameFirmCount > 1) {
            cv.result = 'multiple'; cv.id = firstSameFirm.id; cv.officeId = sameFirmOfficeId;
            cv.html = email + ' matches <b>' + sameFirmCount + ' contacts</b> at this firm — pick the main one (you can merge the rest later).';
        } else {
            cv.result = 'jobchange'; cv.id = matches[0].Id;
            cv.html = '<b>' + email + '</b> belongs to a contact at a different firm — they\'ve likely <b>changed jobs</b>. We\'ll create a new contact here (you can mark the old one as having left).';
        }
        v.contact = cv;
    }

    private static Banner bannerOf(View v) {
        Banner b = new Banner();
        if (v.firmNoOffice) {
            b.cls = 'info'; b.ic = 'company';
            b.html = '<b>We found the firm, but it has no office here yet.</b> We\'ll add the first office under it — keeping the firm\'s totals intact, with no stray records.';
        } else if (v.contact != null && v.contact.result == 'found') {
            b.cls = 'info'; b.ic = 'link';
            b.html = '<b>This person already exists</b> at this firm — we\'ll link the enquiry to them instead of creating a second record.';
        } else if (!v.hasFirm && !v.ambiguous) {
            b.cls = 'ok'; b.ic = 'add';
            b.html = '<b>This looks genuinely new.</b> Our duplicate checks came back clean, so we\'ll set up a new firm with its first office.';
        } else if (v.ambiguous) {
            b.cls = 'warn'; b.ic = 'warning';
            b.html = '<b>More than one firm shares this domain.</b> Pick carefully — your choice decides where the contact and any deal live, and a wrong pick means Data Team cleanup. '
                + 'Compare each firm\'s domain and footprint (offices · contacts · won deals) against the lead\'s email; if you\'re not sure, check the firm\'s website before converting.';
        } else if (v.conflict) {
            b.cls = 'warn'; b.ic = 'scale';
            b.html = '<b>We go by location, not deal volume.</b> Another office has more opportunities, but the lead\'s location decides where they land — and that office\'s address goes onto the contact. Opportunity count only breaks a tie.';
        } else if (v.hasOpenBrandOpp) {
            // genuine duplicate: an open deal already covers this brand — don't create a second
            b.cls = 'warn'; b.ic = 'opportunity';
            b.html = '<b>There\'s already an open ' + (v.brand != null ? v.brand + ' ' : '')
                + 'opportunity at this firm.</b> Convert and link the enquiry to it rather than creating a second — or disqualify it as a duplicate enquiry.';
        } else if (v.oppMotion == 'Renewal') {
            b.cls = 'ok'; b.ic = 'refresh';
            String ends = (v.renewalDate != null) ? (' Their current term ends ' + v.renewalDate.format() + '.') : '';
            b.html = '<b>Existing ' + v.brand + ' customer — renewal opportunity.</b>' + ends
                + ' Convert into the existing office and create the renewal.';
        } else if (v.oppMotion == 'Upsell') {
            b.cls = 'ok'; b.ic = 'trending';
            b.html = '<b>Existing ' + v.brand + ' customer — upsell opportunity.</b> Convert into the existing office and add the expansion opportunity (no new account needed).';
        } else if (v.oppMotion == 'Cross-sell') {
            b.cls = 'info'; b.ic = 'wand';
            b.html = (v.familyCustomer == true && String.isNotBlank(v.brandFamily))
                ? ('<b>Existing ' + v.brandFamily + ' client — cross-sell into ' + v.brand + '.</b> They already subscribe to another '
                    + v.brandFamily + ' title but not ' + v.brand + ' — a warm cross-sell. Convert into the existing office.')
                : ('<b>Existing client' + (v.brand != null ? ', new to ' + v.brand : '') + ' — cross-sell opportunity.</b> They already do business with us, just not on this '
                    + (v.brand != null ? 'brand' : 'line') + '. Convert into the existing office.');
        } else if (v.brand != null && v.brandStatus == 'prospect') {
            b.cls = 'info'; b.ic = 'trending';
            b.html = '<b>New to ' + v.brand + '.</b> They don\'t have an active ' + v.brand
                + ' subscription at this firm (they may subscribe to other brands) — a real ' + v.brand + ' opportunity.';
        } else {
            b.cls = 'info'; b.ic = 'location';
            b.html = 'We\'ve pre-selected the best office by location, then by opportunity activity. Just confirm before you convert.';
        }
        return b;
    }

    private static String money(Decimal v) {
        if (v == null) return '£0';
        if (v >= 1000000) return '£' + (v / 1000000).setScale(2) + 'M';
        if (v >= 1000) return '£' + (v / 1000).setScale(0) + 'k';
        return '£' + v.setScale(0);
    }

    /** Format a Date as "d MMM yyyy" (e.g. 12 Jul 2026); blank for null. */
    private static String fmtDate(Date d) {
        if (d == null) return '';
        return Datetime.newInstance(d.year(), d.month(), d.day()).format('d MMM yyyy');
    }
}
