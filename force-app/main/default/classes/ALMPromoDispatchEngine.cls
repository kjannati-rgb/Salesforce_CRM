/**
 * REV-60 — ALM Promo & Dispatch code derivation engine.
 *
 * Sibling of the REV-71 ALM invoice-code engine. Stamps Promo_Code__c and
 * Dispatch_Method_Code__c on ALM-only quote lines / opportunity products.
 *
 * DESIGN — Flow-orchestrated, Apex-derived hybrid:
 *   - The two layer FLOWS (Quote_ALM_PromoDispatch_Stamp via Quote_AfterSave_MasterFlow,
 *     and Opp_ALM_PromoDispatch_AfterSave) own triggering, the CMDT kill switches, the
 *     org bypass, and fault logging (PFC_Log_Fault) — same declarative contract as REV-71.
 *   - This class owns the per-line logic. The pure derive()/helpers take ALL config as
 *     parameters (dependency injection) so they are exhaustively unit-testable WITHOUT
 *     deployed Custom Metadata, kill-switch state, or the CPQ calculation service. The layer
 *     runners do the I/O (deep queries -> DerivContext) and the @InvocableMethod wrappers
 *     read the CMDT and delegate.
 *
 * COMPOSITION (confirmed — QSS "Codes for Sales" sheet + Willie/Brady, 26 Jun 2026):
 *     Promo_Code__c = Base + Frequency + YearTerm + Modifier
 *       Base      = firm segment (A->!AMLW, N->!NLJO, G->!GLBL); else Non-AmLaw cascade:
 *                   default !SJSI -> team override (Shawn Harlan's team -> !SGRP)
 *                   -> campaign override (!SREN/!MCLG, pending Brady)
 *       Frequency = "" (annual) | M (monthly) | Q (quarterly) | H (semi-annual)  [SBQQ__BillingFrequency__c]
 *       YearTerm  = "" (year 1) | Y2 | Y3 | Y4 | Y5                              [SBQQ__SubscriptionTerm__c / 12]
 *       Modifier  = Z (deal contains a Mid Market Pro product) | ""             (P / Law Premium retired)
 *     Segment is read on the FIRM: Opportunity.Account.Ultimate_Account__r.Model_Segmentation__c.
 *     Dispatch keys on product/licence (separate determinant): ON/OS/OE/OL/ME/PO.
 *
 * GUARDRAILS (spec §6): ALM-scoped only; strictly additive (write only when blank or ALM-owned);
 * never overwrite a legacy LBR value; never write a P* (print) dispatch to an ALM line.
 *
 * Runs without sharing to mirror REV-71's SystemModeWithoutSharing flows.
 */
public without sharing class ALMPromoDispatchEngine {

    // ====================================================================
    // Invocable surface — called by the Layer 1 / Layer 2 flows
    // ====================================================================
    public class FlowResult {
        @InvocableVariable public Boolean ran = false;
        @InvocableVariable public Integer recordsUpdated = 0;
        @InvocableVariable public String faultMessage;
        @InvocableVariable public String visibilityMessage;
        @InvocableVariable public Boolean hasGap = false;   // backstop: an in-scope ALM line is still missing a required code
        @InvocableVariable public String gapMessage;        // human-readable list for the save-time Custom Error
    }

    @InvocableMethod(label='REV-60 Stamp ALM Promo/Dispatch — Layer 1 (Quote)'
        description='Derives & stamps Promo_Code__c / Dispatch_Method_Code__c on the quote\'s ALM lines, reconciling OLIs when the quote is primary. CMDT-driven, additive, kill-switchable.')
    public static List<FlowResult> stampQuote(List<Id> quoteIds) {
        return runLayer1(quoteIds, loadConfig());
    }

    /** Layer 2 entry point. The @InvocableMethod wrapper lives in ALMPromoDispatchOppAction
        (Apex allows only one @InvocableMethod per class). */
    public static List<FlowResult> stampOpportunity(List<Id> opportunityIds) {
        return runLayer2(opportunityIds, loadConfig());
    }

    // ====================================================================
    // Layer runners — query + build context + derive + DML. cfg injected for testability.
    // ====================================================================
    @TestVisible
    static List<FlowResult> runLayer1(List<Id> quoteIds, EngineConfig cfg) {
        Map<Id, FlowResult> byQuote = new Map<Id, FlowResult>();
        for (Id qId : quoteIds) byQuote.put(qId, new FlowResult());
        if (cfg == null || !cfg.masterActive || !cfg.layer1Active) {
            return ordered(quoteIds, byQuote);
        }
        try {
            Map<Id, SBQQ__Quote__c> quotes = new Map<Id, SBQQ__Quote__c>([
                SELECT Id, SBQQ__Primary__c, SBQQ__Opportunity2__c,
                       SBQQ__SubscriptionTerm__c, SBQQ__BillingFrequency__c,
                       SBQQ__SalesRep__r.Name,
                       SBQQ__Opportunity2__r.Type,
                       SBQQ__Opportunity2__r.Owner.Name,
                       SBQQ__Opportunity2__r.Owner.UserRole.Name,
                       SBQQ__Opportunity2__r.Account.Model_Segmentation__c,
                       SBQQ__Opportunity2__r.Account.Ultimate_Account__r.Model_Segmentation__c
                FROM SBQQ__Quote__c WHERE Id IN :quoteIds
            ]);
            Map<Id, List<SBQQ__QuoteLine__c>> linesByQuote = new Map<Id, List<SBQQ__QuoteLine__c>>();
            for (SBQQ__QuoteLine__c ln : [
                SELECT Id, SBQQ__Quote__c, SBQQ__ProductCode__c, Promo_Code__c, Dispatch_Method_Code__c,
                       SBQQ__RequiredBy__c, SBQQ__ProductOption__c, CurrencyIsoCode, CreatedDate,
                       SBQQ__BillingFrequency__c, SBQQ__SubscriptionTerm__c
                FROM SBQQ__QuoteLine__c WHERE SBQQ__Quote__c IN :quoteIds
            ]) {
                if (!linesByQuote.containsKey(ln.SBQQ__Quote__c)) linesByQuote.put(ln.SBQQ__Quote__c, new List<SBQQ__QuoteLine__c>());
                linesByQuote.get(ln.SBQQ__Quote__c).add(ln);
            }
            Map<Id, SObject> qlUpdates = new Map<Id, SObject>();
            Map<Id, Id> primaryOppByQuote = new Map<Id, Id>();
            Map<Id, DerivContext> ctxByQuote = new Map<Id, DerivContext>();
            for (Id qId : quoteIds) {
                FlowResult fr = byQuote.get(qId);
                fr.ran = true;
                SBQQ__Quote__c q = quotes.get(qId);
                Opportunity opp = (q != null) ? q.SBQQ__Opportunity2__r : null;
                DerivContext ctx = buildContext(opp, linesByQuote.get(qId), FIELDS_QL, cfg);
                if (q != null) {                                     // real CPQ holds term/frequency on the Quote, not the
                    ctx.quoteTerm = q.SBQQ__SubscriptionTerm__c;     // line — use as the fallback so a multiyear deal gets the
                    ctx.quoteFrequency = q.SBQQ__BillingFrequency__c;// correct Yn suffix (REV-60 UAT A2/A3 fix, 7 Jul)
                    // Benefitting-group rep signal: the quote's Sales Rep, falling back to the Opp owner.
                    String repName = (q.SBQQ__SalesRep__r != null) ? q.SBQQ__SalesRep__r.Name : null;
                    if (String.isBlank(repName) && opp != null && opp.Owner != null) repName = opp.Owner.Name;
                    ctx.repSignal = resolveRepSignal(repName, cfg);
                }
                ctxByQuote.put(qId, ctx);
                ApplyOutcome o = applyToRecords(linesByQuote.get(qId), cfg, FIELDS_QL, ctx);
                for (SObject u : o.updates) qlUpdates.put((Id) u.get('Id'), u);
                fr.recordsUpdated += o.updates.size();
                fr.visibilityMessage = cfg.byKey.isEmpty() ? null : summarise(o.notes, qId);
                fr.hasGap = o.missingCount > 0;
                fr.gapMessage = gapSummary(o, cfg);
                if (q != null && q.SBQQ__Primary__c == true && q.SBQQ__Opportunity2__c != null) {
                    primaryOppByQuote.put(qId, q.SBQQ__Opportunity2__c);
                }
            }
            if (!qlUpdates.isEmpty()) update qlUpdates.values();

            // Primary-quote OLI reconciliation — CPQ twin-field sync lags one save on updates.
            // Reuses the quote's context (same opportunity / same deal).
            if (!primaryOppByQuote.isEmpty()) {
                Set<Id> oppIds = new Set<Id>(primaryOppByQuote.values());
                Map<Id, List<OpportunityLineItem>> olisByOpp = groupOlis([
                    SELECT Id, OpportunityId, ProductCode, Promo_Code__c, Dispatch_Method_Code__c, SBQQ__ParentID__c, CurrencyIsoCode, CreatedDate
                    FROM OpportunityLineItem WHERE OpportunityId IN :oppIds
                ]);
                Map<Id, SObject> oliUpdates = new Map<Id, SObject>();
                for (Id qId : primaryOppByQuote.keySet()) {
                    ApplyOutcome o = applyToRecords(olisByOpp.get(primaryOppByQuote.get(qId)), cfg, FIELDS_OLI, ctxByQuote.get(qId));
                    for (SObject u : o.updates) oliUpdates.put((Id) u.get('Id'), u);
                    byQuote.get(qId).recordsUpdated += o.updates.size();
                }
                if (!oliUpdates.isEmpty()) update oliUpdates.values();
            }
        } catch (Exception e) {
            for (Id qId : quoteIds) byQuote.get(qId).faultMessage = 'REV-60 Layer 1 fault on quote ' + qId + ': ' + e.getMessage();
            logFault('REV-60 Layer 1 — flow fault', e.getMessage() + ' :: ' + e.getStackTraceString(), quoteIds.isEmpty() ? null : String.valueOf(quoteIds[0]));
        }
        return ordered(quoteIds, byQuote);
    }

    @TestVisible
    static List<FlowResult> runLayer2(List<Id> oppIds, EngineConfig cfg) {
        Map<Id, FlowResult> byOpp = new Map<Id, FlowResult>();
        for (Id oId : oppIds) byOpp.put(oId, new FlowResult());
        if (cfg == null || !cfg.masterActive || !cfg.layer2Active) {
            return ordered(oppIds, byOpp);
        }
        try {
            Map<Id, List<OpportunityLineItem>> olisByOpp = groupOlis([
                SELECT Id, OpportunityId, ProductCode, Promo_Code__c, Dispatch_Method_Code__c, SBQQ__ParentID__c, CurrencyIsoCode, CreatedDate,
                       Opportunity.Type, Opportunity.Owner.Name, Opportunity.Owner.UserRole.Name,
                       Opportunity.Account.Model_Segmentation__c,
                       Opportunity.Account.Ultimate_Account__r.Model_Segmentation__c,
                       Opportunity.SBQQ__PrimaryQuote__r.SBQQ__SubscriptionTerm__c,
                       Opportunity.SBQQ__PrimaryQuote__r.SBQQ__BillingFrequency__c
                FROM OpportunityLineItem WHERE OpportunityId IN :oppIds
            ]);
            Map<Id, SObject> updates = new Map<Id, SObject>();
            for (Id oId : oppIds) {
                FlowResult fr = byOpp.get(oId);
                fr.ran = true;
                List<OpportunityLineItem> olis = olisByOpp.get(oId);
                Opportunity opp = (olis != null && !olis.isEmpty()) ? olis[0].Opportunity : null;
                DerivContext ctx = buildContext(opp, olis, FIELDS_OLI, cfg);
                applyPrimaryQuoteContext(ctx, opp);
                ApplyOutcome o = applyToRecords(olis, cfg, FIELDS_OLI, ctx);
                for (SObject u : o.updates) updates.put((Id) u.get('Id'), u);
                fr.recordsUpdated += o.updates.size();
                fr.visibilityMessage = cfg.byKey.isEmpty() ? null : summarise(o.notes, oId);
                fr.hasGap = o.missingCount > 0;
                fr.gapMessage = gapSummary(o, cfg);
            }
            if (!updates.isEmpty()) update updates.values();
        } catch (Exception e) {
            for (Id oId : oppIds) byOpp.get(oId).faultMessage = 'REV-60 Layer 2 fault on opportunity ' + oId + ': ' + e.getMessage();
            logFault('REV-60 Layer 2 — flow fault', e.getMessage() + ' :: ' + e.getStackTraceString(), oppIds.isEmpty() ? null : String.valueOf(oppIds[0]));
        }
        return ordered(oppIds, byOpp);
    }

    // ====================================================================
    // Context resolution (deep-query inputs -> per-deal signals)
    // ====================================================================
    public class DerivContext {
        public String segment;         // firm Model_Segmentation (A/N/G/O/null)
        public String teamSignal;      // resolved from the owner's role (Non-AmLaw !SGRP / !SREN split)
        public String campaignSignal;  // campaign / outreach type (!MCLG — pending Brady)
        public String oppType;         // Opportunity Type — gates type-scoped team overrides (WNS -> !SREN)
        public Decimal quoteTerm;      // Quote-level SBQQ__SubscriptionTerm__c — fallback when the line's is blank (real CPQ holds the term on the Quote, not the line)
        public String quoteFrequency;  // Quote-level SBQQ__BillingFrequency__c — QUOTE-FIRST (the line value is CPQ product-default noise)
        public String repSignal;       // matched Rep Override key (benefitting-group reps -> !EMEA/BE, !APAC/BA)
        public Boolean isMidMarketPro = false; // deal contains a Mid Market Pro Bundle line -> +Z on the deal's ALM lines
    }

    @TestVisible
    static DerivContext buildContext(Opportunity opp, List<SObject> records, FieldSet fs, EngineConfig cfg) {
        DerivContext ctx = new DerivContext();
        if (opp != null) {
            ctx.segment = firmSegment(opp);
            ctx.teamSignal = resolveTeamSignal(ownerRole(opp), cfg);
            ctx.oppType = opp.Type;
            if (opp.Owner != null) ctx.repSignal = resolveRepSignal(opp.Owner.Name, cfg); // Layer 2: no quote Sales Rep — owner only
            // ctx.campaignSignal — pending Brady's !MCLG trigger definition.
        }
        ctx.isMidMarketPro = hasMidMarketProduct(records, fs, cfg);
        return ctx;
    }

    /** Layer 2's term/frequency source is the opp's PRIMARY QUOTE — OLIs carry neither, so without
        this a 5-year deal reads as year 1 and Layer 2 DOWNGRADES the synced !AMLWY5 to !AMLW
        (UAT round 4 B2, Cindy's 'cindy test - amlaw 5 year'). */
    @TestVisible
    static void applyPrimaryQuoteContext(DerivContext ctx, Opportunity opp) {
        if (ctx == null || opp == null || opp.SBQQ__PrimaryQuote__r == null) return;
        ctx.quoteTerm = opp.SBQQ__PrimaryQuote__r.SBQQ__SubscriptionTerm__c;
        ctx.quoteFrequency = opp.SBQQ__PrimaryQuote__r.SBQQ__BillingFrequency__c;
    }

    /** Deal-level +Z trigger: any line on the deal carries a configured Mid Market Pro product code
        (the Law.com line itself has no bundle marker, so this is a sibling scan). */
    @TestVisible
    static Boolean hasMidMarketProduct(List<SObject> records, FieldSet fs, EngineConfig cfg) {
        if (records == null || cfg.midMarketProProductCodes.isEmpty()) return false;
        for (SObject rec : records) {
            String pc = str(rec.get(fs.product));
            if (pc != null && cfg.midMarketProProductCodes.contains(pc)) return true;
        }
        return false;
    }

    /** Rep signal = the Rep Override key (a User full name) matching the deal's sales rep. Exact,
        case-insensitive match — these are specific named people (Cindy/Michael, 7 Jul: Charlie Murray +
        Caitlin Greaves -> !EMEA/BE, Joey Kwok -> !APAC/BA). NB "Grieves" in the request email is a
        misspelling; the User record is Caitlin GREAVES. */
    @TestVisible
    static String resolveRepSignal(String repName, EngineConfig cfg) {
        if (String.isBlank(repName)) return null;
        for (String key : cfg.repOverrides.keySet()) {
            if (key != null && key.equalsIgnoreCase(repName)) return key;
        }
        for (String key : cfg.repOverrideDispatch.keySet()) {
            if (key != null && key.equalsIgnoreCase(repName)) return key;
        }
        return null;
    }

    /** Segment on the firm (Ultimate_Account), falling back to the buying account. */
    static String firmSegment(Opportunity opp) {
        if (opp == null || opp.Account == null) return null;
        String seg = (opp.Account.Ultimate_Account__r != null) ? opp.Account.Ultimate_Account__r.Model_Segmentation__c : null;
        if (String.isBlank(seg)) seg = opp.Account.Model_Segmentation__c;
        return seg;
    }

    static String ownerRole(Opportunity opp) {
        if (opp == null || opp.Owner == null || opp.Owner.UserRole == null) return null;
        return opp.Owner.UserRole.Name;
    }

    /** Team signal = the team-override key whose marker the owner's role contains (e.g. the
        "Global Enterprise Solutions & Memberships" branch -> Shawn Harlan's team -> !SGRP). */
    @TestVisible
    static String resolveTeamSignal(String role, EngineConfig cfg) {
        if (String.isBlank(role)) return null;
        for (String key : cfg.teamOverrides.keySet()) {
            if (key != null && role.contains(key)) return key;
        }
        return null;
    }

    // ====================================================================
    // Generic per-record application (QuoteLine or OLI, via FieldSet + context)
    // ====================================================================
    @TestVisible
    static ApplyOutcome applyToRecords(List<SObject> records, EngineConfig cfg, FieldSet fs, DerivContext ctx) {
        ApplyOutcome out = new ApplyOutcome();
        if (records == null) return out;
        for (SObject rec : records) {
            // Bundle children are normally excluded (invoiced through the parent — e.g. Law.com Pro,
            // whose PARENT carries the code). EXCEPTION: Mid Market Pro Bundle children ARE the invoiced
            // subscriptions and carry full promos in PROD (child LAWM lines = !AMLWY3Z etc., 16 Jul,
            // Cindy UAT E2) — so on an MMPro deal the children are derived like any line (+Z).
            if (isChild(rec, fs) && !(ctx != null && ctx.isMidMarketPro == true)) continue;
            Request req = new Request();
            req.recordId = (Id) rec.get('Id');
            req.productCode = str(rec.get(fs.product));
            req.determinantKey = (ctx != null) ? ctx.segment : str(rec.get(fs.product));
            req.teamSignal = (ctx != null) ? ctx.teamSignal : null;
            req.campaignSignal = (ctx != null) ? ctx.campaignSignal : null;
            req.oppType = (ctx != null) ? ctx.oppType : null;
            req.repSignal = (ctx != null) ? ctx.repSignal : null;
            req.isMidMarketPro = (ctx != null && ctx.isMidMarketPro == true);
            try { req.currencyCode = str(rec.get('CurrencyIsoCode')); } catch (Exception ex) { /* single-currency org */ }
            try { req.lineCreatedDate = (Datetime) rec.get('CreatedDate'); } catch (Exception ex) { /* CreatedDate not queried on this record */ }
            req.contractYearIndex = resolveYearIndex(rec, cfg, ctx);
            req.frequencyCode = resolveFrequency(rec, cfg, ctx);
            req.currentPromo = str(rec.get(fs.promo));
            req.currentDispatch = str(rec.get(fs.dispatch));
            Result r = derive(cfg, req);
            if (r.writePromo || r.writeDispatch) {
                SObject upd = rec.getSObjectType().newSObject(req.recordId);
                if (r.writePromo) upd.put(fs.promo, r.promoToWrite);
                if (r.writeDispatch) upd.put(fs.dispatch, r.dispatchToWrite);
                out.updates.add(upd);
            }
            if (r.inScope && r.skipReason != null && !r.writePromo && !r.writeDispatch) {
                out.notes.add(req.recordId + ': ' + r.skipReason);
            }
            if (r.missingPromo || r.missingDispatch) {
                out.missingCount++;
                String which = (r.missingPromo && r.missingDispatch) ? 'promo+dispatch' : (r.missingPromo ? 'promo' : 'dispatch');
                out.gaps.add(blankToEmpty(req.productCode) + ' (' + which + ')');
            }
        }
        return out;
    }

    // ====================================================================
    // Pure derivation — the exhaustively unit-tested core
    // ====================================================================
    @TestVisible
    static Result derive(EngineConfig cfg, Request r) {
        Result res = new Result();
        res.recordId = r.recordId;

        // Scope gate (§6.1) — only ever act on configured ALM products.
        if (String.isBlank(r.productCode) || !cfg.almProductCodes.contains(r.productCode)) {
            res.skipReason = 'Out of ALM scope';
            return res;
        }
        res.inScope = true;

        // Base = product-fixed (GLBM->MSHP) | ranked segment | Non-AmLaw cascade. Promo applies only
        // to the Law.com umbrella + product-fixed products; print/online lines are dispatch-only.
        MapEntry e = (r.determinantKey != null) ? cfg.byKey.get(r.determinantKey) : null;
        Boolean applyYear = (e == null) ? true : (e.applyYearSuffix == true);
        ResolvedBase rb = resolveBase(cfg, r, e);
        String base = rb.base;

        if (rb.promoApplies) {
            if (String.isNotBlank(base)) {
                String composed = rb.plainBase ? (base + modifier(cfg, r)) : compose(cfg, r, base, applyYear);
                // A blank-only default (WNS !SREN) is only ever stamped onto a blank line, so a rep's
                // !SJSI-vs-!SREN choice always wins; deterministic bases use the normal additive guard.
                Boolean writable = rb.blankOnly ? String.isBlank(r.currentPromo) : isPromoWritable(cfg, r.currentPromo, composed);
                if (writable) {
                    res.writePromo = true;
                    res.promoToWrite = composed;
                }
            } else {
                res.skipReason = 'No base for determinant "' + r.determinantKey + '" (no segment match, no default base)';
            }
        }
        // else: dispatch-only product (print/online) — no promo derivation, not flagged as a gap.

        // Dispatch = deterministic product code (GLBM->ME, NYLM->PO), write-on-blank-only — never
        // overwrite a rep's OS/OE/OL or a legacy value. Law.com/LWKM/NYOM dispatch stays rep-entered.
        String dispatch = resolveDispatch(cfg, r, e);
        if (String.isNotBlank(dispatch) && isDispatchWritable(cfg, r.currentDispatch, dispatch)) {
            res.writeDispatch = true;
            res.dispatchToWrite = dispatch;
        }

        // Backstop signals — a genuine gap is an in-scope ALM line still missing a REQUIRED code
        // AFTER the engine has filled everything it can: promo for promo-applicable products, dispatch
        // for products that require one (rep-choice dispatch the engine can't derive). The save-time
        // flow raises a Custom Error on these; print/online promo and non-required dispatch never flag.
        String effPromo = res.writePromo ? res.promoToWrite : r.currentPromo;
        res.missingPromo = rb.promoApplies && String.isBlank(effPromo);
        String effDispatch = res.writeDispatch ? res.dispatchToWrite : r.currentDispatch;
        res.missingDispatch = cfg.dispatchRequiredProducts.contains(r.productCode)
            && String.isBlank(effDispatch)
            && dispatchEnforceable(cfg, r);
        return res;
    }

    /** Grandfathering gate for the dispatch backstop. A required-but-blank dispatch is only flagged
        (and so only hard-blocks the save) on lines created ON/AFTER the configured cutoff — so re-arming
        LAWM/LWKM/NYOM enforces genuinely NEW lines while never blocking the legacy open quotes.
        cutoff == null  -> enforce always (original behaviour; keeps GLBM/NYLM enforcement unchanged).
        lineCreatedDate == null (undatable / not queried) -> grandfather (never block a line we can't date). */
    @TestVisible
    static Boolean dispatchEnforceable(EngineConfig cfg, Request r) {
        if (cfg.enforceDispatchAfter == null) return true;
        if (r.lineCreatedDate == null) return false;
        return r.lineCreatedDate >= cfg.enforceDispatchAfter;
    }

    public class ResolvedBase {
        public String base;
        public Boolean blankOnly = false;   // non-deterministic default — fill a blank, never overwrite a rep's choice
        public Boolean promoApplies = true; // false for dispatch-only products (print/online) — no promo derivation
        public Boolean plainBase = false;   // product-base row with Apply_Year_Suffix=false — write the bare base, no freq/year composition (PCE01/02/03)
    }

    // ---- base resolution: ranked segment, else the Non-AmLaw override cascade ----
    /** Base = ranked-segment lookup (A->!AMLW, N->!NLJO, G->!GLBL) when the determinant matches a
        configured row; otherwise the Non-AmLaw cascade — default (!SJSI), overridden by the owning
        team (Shawn -> !SGRP any type; WNS -> !SREN on Renewal/Upsell), then by campaign (!MCLG).
        A team override flagged write-on-blank-only (WNS !SREN) returns blankOnly=true: it's a smart
        default the rep can change, so the engine only fills it on a blank and never overwrites. */
    @TestVisible
    static ResolvedBase resolveBase(EngineConfig cfg, Request r, MapEntry e) {
        ResolvedBase rb = new ResolvedBase();
        // (1) Product-level fixed base wins outright — not segment-driven. A currency-qualified row
        //     ("PCEM|USD" -> PCE01, Cindy 13 Jul: PCE promo is per-currency) beats the plain product row.
        if (r.productCode != null) {
            String ccyKey = String.isBlank(r.currencyCode) ? null : r.productCode + '|' + r.currencyCode.trim().toUpperCase();
            String hit = (ccyKey != null && cfg.productBase.containsKey(ccyKey)) ? ccyKey
                       : (cfg.productBase.containsKey(r.productCode) ? r.productCode : null);
            if (hit != null) {
                rb.base = cfg.productBase.get(hit);
                rb.plainBase = cfg.productBasePlain.contains(hit); // row says no year/freq suffixes (PCE01, not PCE01QY3)
                return rb;
            }
        }
        // (2) The firm-segment cascade applies ONLY to the Law.com umbrella products. Print/online
        //     (NYLM/NYOM) and anything else carry no promo — they are dispatch-only.
        if (r.productCode == null || !cfg.segmentPromoProducts.contains(r.productCode)) {
            rb.promoApplies = false;
            return rb;
        }
        // (3) BENEFITTING-GROUP REP override — beats the firm ranking (Finance/Laurie Melzi 16 Jul:
        //     "!EMEA/!APAC used regardless of ranking"; segmentation ties to revenue rules, not promo).
        //     Product-fixed bases (step 1: GLBM/PCGE) still win — those coding schemes are per-product.
        if (r.repSignal != null && cfg.repOverrides.containsKey(r.repSignal)) {
            rb.base = cfg.repOverrides.get(r.repSignal);                          // Charlie/Caitlin -> !EMEA; Joey -> !APAC
            return rb;
        }
        // (4) Ranked segment -> deterministic base (A->!AMLW, N->!NLJO, G->!GLBL).
        if (e != null && String.isNotBlank(e.basePromo)) {
            rb.base = e.basePromo;
            return rb;
        }
        // (5) Non-AmLaw cascade: default (!SJSI) -> team override -> campaign override.
        rb.base = blankToEmpty(cfg.defaultBase);                                  // Non-AmLaw default (!SJSI)
        if (r.teamSignal != null && cfg.teamOverrides.containsKey(r.teamSignal)) {
            Set<String> allowedTypes = cfg.teamOverrideTypes.get(r.teamSignal);   // empty/null = applies to any Opp Type
            if (allowedTypes == null || allowedTypes.isEmpty() || (r.oppType != null && allowedTypes.contains(r.oppType))) {
                rb.base = cfg.teamOverrides.get(r.teamSignal);                    // Shawn -> !SGRP (any); WNS -> !SREN (Renewal/Upsell)
                rb.blankOnly = cfg.teamOverrideBlankOnly.contains(r.teamSignal);
            }
        }
        if (r.campaignSignal != null && cfg.campaignOverrides.containsKey(r.campaignSignal)) {
            rb.base = cfg.campaignOverrides.get(r.campaignSignal);                // legacy campaign -> !MCLG
            rb.blankOnly = false;
        }
        return rb;
    }

    /** Dispatch keys on product/licence — a separate determinant from the promo base. A product-fixed
        code (GLBM->ME, NYLM->PO) wins; else a benefitting-group rep's code (Charlie/Caitlin->BE,
        Joey->BA) applies to their Law.com lines; else the determinant-entry fallback. */
    static String resolveDispatch(EngineConfig cfg, Request r, MapEntry e) {
        if (r.productCode != null && cfg.dispatchByProduct.containsKey(r.productCode)) {
            return blankToEmpty(cfg.dispatchByProduct.get(r.productCode));
        }
        if (r.repSignal != null && cfg.repOverrideDispatch.containsKey(r.repSignal)) {
            return blankToEmpty(cfg.repOverrideDispatch.get(r.repSignal));
        }
        return (e != null) ? blankToEmpty(e.dispatchCode) : '';
    }

    // ---- composition (base + frequency + yearTerm + modifier) ----
    @TestVisible
    static String compose(EngineConfig cfg, Request r, String base, Boolean applyYear) {
        String freq = (r.frequencyCode == null) ? '' : r.frequencyCode;
        String yr = (cfg.yearSuffixEnabled && applyYear) ? yearSuffix(r.contractYearIndex) : '';
        return base + freq + yr + modifier(cfg, r);
    }

    static String yearSuffix(Decimal idx0) {
        Integer idx = (idx0 == null) ? 1 : idx0.intValue();
        if (idx == 2) return 'Y2';
        if (idx == 3) return 'Y3';
        if (idx == 4) return 'Y4';
        if (idx == 5) return 'Y5';
        return ''; // year 1 (or out of range) is unsuffixed
    }

    /** Z applies when (a) the deal contains a Mid Market Pro Bundle line — a 100% rule in PROD
        (every LAWM line on a bundle quote carries Z, 43/43, checked 15 Jul; Cindy UAT E2) — or
        (b) the rep already typed a trailing Z (Z is also used WITHOUT the bundle — only 32% of
        Z deals carry it — so a rep's Z is always PRESERVED, never stripped, never required).
        The P / Law Premium modifier was retired 26 Jun. */
    static String modifier(EngineConfig cfg, Request r) {
        if (r.isMidMarketPro == true) return 'Z';
        return (r.currentPromo != null && r.currentPromo.endsWith('Z')) ? 'Z' : '';
    }

    // ---- additive write guards (§4) ----
    @TestVisible
    static Boolean isPromoWritable(EngineConfig cfg, String current, String composed) {
        if (String.isBlank(current)) return true;          // blank -> fill
        if (current == composed) return false;             // already correct -> idempotent no-op
        return isAlmOwnedPromo(cfg, current);              // ALM-owned -> may refresh; legacy -> never
    }

    /** ALM-owned = a configured base followed by an optional Frequency (M/Q/H), Year (Y2-Y5),
        and Modifier (Z/P). Prefix-match (not blind stripping) so bases that end in P/M/Q/H —
        e.g. MSHP, !SGRP — are handled correctly. */
    @TestVisible
    static Boolean isAlmOwnedPromo(EngineConfig cfg, String current) {
        if (String.isBlank(current)) return false;
        for (String b : cfg.allKnownBases()) {
            if (matchesBase(current, b)) return true;
        }
        return false;
    }

    static Boolean matchesBase(String current, String base) {
        if (String.isBlank(base) || !current.startsWith(base)) return false;
        return isValidSuffix(current.substring(base.length()));
    }

    /** Validates an optional Frequency + Year + Modifier tail (composition order). The Z|P
        modifier is accepted so legacy P-suffixed codes still register as ALM-owned for cleanup,
        even though P is no longer written. */
    @TestVisible
    static Boolean isValidSuffix(String rem) {
        String s = (rem == null) ? '' : rem;
        if (s.length() >= 1) {
            String f = s.substring(0, 1);
            if (f == 'M' || f == 'Q' || f == 'H') s = s.substring(1);
        }
        if (s.length() >= 2) {
            String y = s.substring(0, 2);
            if (y == 'Y2' || y == 'Y3' || y == 'Y4' || y == 'Y5') s = s.substring(2);
        }
        if (s == 'Z' || s == 'P') s = '';
        return s == '';
    }

    @TestVisible
    static Boolean isDispatchWritable(EngineConfig cfg, String current, String resolved) {
        // Write-on-blank-only: the engine auto-fills only the deterministic products (GLBM->ME,
        // NYLM->PO) and only onto a blank line. A rep's OS/OE/OL or any legacy value is never overwritten.
        return String.isBlank(current);
    }

    // ====================================================================
    // CMDT config loader (covered by the inert invocable path test)
    // ====================================================================
    @TestVisible
    static EngineConfig loadConfig() {
        EngineConfig cfg = new EngineConfig();
        ALM_Code_Engine_Settings__mdt s;
        try { s = ALM_Code_Engine_Settings__mdt.getInstance('Control'); } catch (Exception ex) { s = null; }
        if (s != null) {
            cfg.masterActive       = s.Master_Active__c == true;
            cfg.layer1Active       = s.Layer_1_Active__c == true;
            cfg.layer2Active       = s.Layer_2_Active__c == true;
            cfg.yearSuffixEnabled  = s.Year_Suffix_Enabled__c == true;
            cfg.determinantFieldApi = s.Determinant_Field_API__c;
            cfg.yearFieldApi        = s.Contract_Year_Field_API__c;
            cfg.frequencyFieldApi   = s.Frequency_Field_API__c;
            cfg.defaultBase         = s.Default_Base_Promo__c;
            cfg.almProductCodes     = splitCsv(s.ALM_Product_Codes__c);
            cfg.segmentPromoProducts = splitCsv(s.Segment_Promo_Product_Codes__c);
            cfg.dispatchRequiredProducts = splitCsv(s.Dispatch_Required_Product_Codes__c);
            cfg.dispatchBackstopHint = s.Dispatch_Backstop_Hint__c;
            cfg.enforceDispatchAfter = s.Enforce_Dispatch_After__c;
            cfg.midMarketProProductCodes = splitCsv(s.Mid_Market_Pro_Product_Codes__c);
        }
        for (ALM_Code_Map__mdt m : ALM_Code_Map__mdt.getAll().values()) {
            if (m.Active__c != true) continue;
            String rt = m.Row_Type__c;
            if (rt == 'Team Override') {
                if (String.isNotBlank(m.Match_Key__c) && String.isNotBlank(m.Base_Promo_Code__c)) {
                    cfg.teamOverrides.put(m.Match_Key__c, m.Base_Promo_Code__c);
                    cfg.teamOverrideTypes.put(m.Match_Key__c, splitCsv(m.Opp_Types__c));
                    if (m.Write_On_Blank_Only__c == true) cfg.teamOverrideBlankOnly.add(m.Match_Key__c);
                }
            } else if (rt == 'Campaign Override') {
                if (String.isNotBlank(m.Match_Key__c) && String.isNotBlank(m.Base_Promo_Code__c)) {
                    cfg.campaignOverrides.put(m.Match_Key__c, m.Base_Promo_Code__c);
                }
            } else if (rt == 'Dispatch') {
                if (String.isNotBlank(m.Match_Key__c) && String.isNotBlank(m.Dispatch_Code__c)) {
                    cfg.dispatchByProduct.put(m.Match_Key__c, m.Dispatch_Code__c);
                    cfg.allDispatch.add(m.Dispatch_Code__c);
                }
            } else if (rt == 'Product Base') {
                if (String.isNotBlank(m.Match_Key__c) && String.isNotBlank(m.Base_Promo_Code__c)) {
                    // Optional currency qualifier: "PCEM" + Currency USD -> key "PCEM|USD" (PCE01/02/03 are per-currency).
                    String pbKey = m.Match_Key__c + (String.isBlank(m.Currency__c) ? '' : '|' + m.Currency__c.trim().toUpperCase());
                    cfg.productBase.put(pbKey, m.Base_Promo_Code__c); // product(+currency) -> fixed base
                    if (m.Apply_Year_Suffix__c != true) cfg.productBasePlain.add(pbKey); // bare base — no freq/year composition
                }
            } else if (rt == 'Rep Override') {
                // Match_Key = semicolon list of User full names; one row per code (!EMEA/BE, !APAC/BA).
                for (String repName : splitCsv(m.Match_Key__c)) {
                    if (String.isNotBlank(m.Base_Promo_Code__c)) cfg.repOverrides.put(repName, m.Base_Promo_Code__c);
                    if (String.isNotBlank(m.Dispatch_Code__c)) {
                        cfg.repOverrideDispatch.put(repName, m.Dispatch_Code__c);
                        cfg.allDispatch.add(m.Dispatch_Code__c);
                    }
                }
            } else { // 'Segment Base' (or legacy null Row_Type)
                MapEntry e = new MapEntry();
                e.matchKey        = m.Match_Key__c;
                e.basePromo       = m.Base_Promo_Code__c;
                e.dispatchCode    = m.Dispatch_Code__c;
                e.applyYearSuffix = m.Apply_Year_Suffix__c == true;
                e.zEligible       = m.Z_Eligible__c == true;
                e.active          = true;
                cfg.addEntry(e);
            }
        }
        return cfg;
    }

    // ====================================================================
    // Field-name binding (lets one code path serve QuoteLine and OLI)
    // ====================================================================
    public class FieldSet {
        public String product, promo, dispatch, child1, child2;
    }
    static final FieldSet FIELDS_QL = buildFs('SBQQ__ProductCode__c', 'Promo_Code__c', 'Dispatch_Method_Code__c', 'SBQQ__RequiredBy__c', 'SBQQ__ProductOption__c');
    static final FieldSet FIELDS_OLI = buildFs('ProductCode', 'Promo_Code__c', 'Dispatch_Method_Code__c', 'SBQQ__ParentID__c', null);

    static FieldSet buildFs(String p, String pr, String d, String c1, String c2) {
        FieldSet f = new FieldSet();
        f.product = p; f.promo = pr; f.dispatch = d; f.child1 = c1; f.child2 = c2;
        return f;
    }

    static Boolean isChild(SObject rec, FieldSet fs) {
        if (fs.child1 != null && rec.get(fs.child1) != null) return true;
        if (fs.child2 != null && rec.get(fs.child2) != null) return true;
        return false;
    }

    @TestVisible
    static Decimal resolveYearIndex(SObject rec, EngineConfig cfg) { return resolveYearIndex(rec, cfg, null); }

    /** §7.3 — contract years. Reads the configured term field off the line; if the line's value is BLANK
        it falls back to the Quote-level term (ctx.quoteTerm). Real CPQ holds the subscription term on the
        Quote, not the line, so without this a 3-year deal reads as year 1 and produces a base-only code
        that the org's "multiyear must have Yn" validation rejects (REV-60 UAT A2/A3). Months (>= 6) are
        divided by 12 to give the year count (e.g. 36 -> Y3).
        NB MDQ segmented (one-line-per-year) quotes deliberately get the DEAL-LENGTH Yn on EVERY segment
        line — PROD convention (Q-217644/Q-217352: !SJSIY3 on Year 1/2/3 segments alike) and the org's
        "multiyear must have Y" validation both demand it (settled in UAT round 4, Cindy's Q-206348). */
    @TestVisible
    static Decimal resolveYearIndex(SObject rec, EngineConfig cfg, DerivContext ctx) {
        Object v = null;
        if (String.isNotBlank(cfg.yearFieldApi)) {
            // rec.get THROWS on an object without the field (OLIs have no SBQQ__SubscriptionTerm__c) —
            // the ctx fallback must live OUTSIDE this try or OLIs never see the quote term and every
            // multiyear deal's products read as year 1 (UAT round 4 B2: !AMLWY5 downgraded to !AMLW).
            try { v = rec.get(cfg.yearFieldApi); } catch (Exception ex) { /* field not on this object */ }
        }
        if (v == null && ctx != null) v = ctx.quoteTerm;   // quote-level term (Layer 1 ctx / Layer 2 primary quote)
        if (v != null) {
            try {
                Decimal raw = Decimal.valueOf(String.valueOf(v));
                return (raw >= 6) ? (raw / 12).setScale(0, System.RoundingMode.HALF_UP) : raw;
            } catch (Exception ex) { /* fall through */ }
        }
        return 1;
    }

    @TestVisible
    static String resolveFrequency(SObject rec, EngineConfig cfg) { return resolveFrequency(rec, cfg, null); }

    /** Billing frequency is QUOTE-FIRST: CPQ stamps the LINE's SBQQ__BillingFrequency__c from the
        product default ('Annual') at add time, so the line value is noise — the rep's real choice
        lives on the Quote (UAT round 2, Q-206292/93: quote=Quarterly, every line='Annual'). The line
        value is only used when there is no quote-level frequency (e.g. Layer 2 OLIs). */
    @TestVisible
    static String resolveFrequency(SObject rec, EngineConfig cfg, DerivContext ctx) {
        if (ctx != null && String.isNotBlank(ctx.quoteFrequency)) return freqCode(ctx.quoteFrequency);
        if (String.isNotBlank(cfg.frequencyFieldApi)) {
            try {
                return freqCode(str(rec.get(cfg.frequencyFieldApi)));
            } catch (Exception ex) { /* fall back */ }
        }
        return '';
    }

    @TestVisible
    static String freqCode(String value) {
        if (String.isBlank(value)) return '';
        String v = value.toLowerCase();
        if (v.startsWith('month')) return 'M';
        if (v.startsWith('quarter')) return 'Q';
        if (v.startsWith('semi')) return 'H';
        return ''; // annual / yearly / multi-year upfront -> unsuffixed
    }

    // ====================================================================
    // Config + DTO model
    // ====================================================================
    public class EngineConfig {
        public Boolean masterActive = false, layer1Active = false, layer2Active = false;
        public Boolean yearSuffixEnabled = true;
        public String determinantFieldApi, yearFieldApi, frequencyFieldApi;
        public String defaultBase; // "else Non-AmLaw" fallback base (e.g. !SJSI)
        public String dispatchBackstopHint; // appended to the backstop error when a dispatch is missing — names the valid codes
        public Datetime enforceDispatchAfter; // dispatch backstop grandfathering: only enforce a required-but-blank dispatch on lines created ON/AFTER this cutoff (null = enforce always). Lets us re-arm LAWM/LWKM/NYOM without hard-blocking the legacy open quotes.
        public Set<String> almProductCodes = new Set<String>();
        public Set<String> segmentPromoProducts = new Set<String>(); // products whose promo = firm-segment cascade (Law.com umbrella)
        public Set<String> dispatchRequiredProducts = new Set<String>(); // products the backstop requires a non-blank dispatch on
        public Set<String> midMarketProProductCodes = new Set<String>(); // deal-level +Z trigger (Mid Market Pro Bundle)
        public Map<String, String> productBase = new Map<String, String>(); // product code (opt. "|CCY") -> fixed base (GLBM -> MSHP, PCEM|USD -> PCE01)
        public Set<String> productBasePlain = new Set<String>(); // product-base keys written as the BARE base (no freq/year suffixes)
        public Map<String, MapEntry> byKey = new Map<String, MapEntry>(); // segment -> base
        public Set<String> allBases = new Set<String>();
        public Set<String> allDispatch = new Set<String>();
        // Non-AmLaw base overrides + product dispatch (config-driven)
        public Map<String, String> teamOverrides = new Map<String, String>();     // team signal -> base (e.g. !SGRP / !SREN)
        public Map<String, Set<String>> teamOverrideTypes = new Map<String, Set<String>>(); // team signal -> allowed Opp Types (empty = any)
        public Set<String> teamOverrideBlankOnly = new Set<String>(); // team keys whose base only fills a blank (never overwrites a rep's choice)
        public Map<String, String> campaignOverrides = new Map<String, String>(); // campaign signal -> base (!MCLG)
        public Map<String, String> dispatchByProduct = new Map<String, String>(); // product code -> dispatch code
        public Map<String, String> repOverrides = new Map<String, String>();         // rep full name -> base (!EMEA / !APAC)
        public Map<String, String> repOverrideDispatch = new Map<String, String>();  // rep full name -> dispatch (BE / BA)

        public void addEntry(MapEntry e) {
            if (e.active != true) return;
            if (String.isNotBlank(e.matchKey)) byKey.put(e.matchKey, e);
            if (String.isNotBlank(e.basePromo)) allBases.add(e.basePromo);
            if (String.isNotBlank(e.dispatchCode)) allDispatch.add(e.dispatchCode);
        }

        /** Every base this engine could author — for the additive ALM-owned guard. */
        public Set<String> allKnownBases() {
            Set<String> b = new Set<String>(allBases);
            if (String.isNotBlank(defaultBase)) b.add(defaultBase);
            b.addAll(teamOverrides.values());
            b.addAll(campaignOverrides.values());
            b.addAll(productBase.values());
            b.addAll(repOverrides.values());
            return b;
        }
    }

    public class MapEntry {
        public String matchKey, basePromo, dispatchCode;
        public Boolean applyYearSuffix = true, zEligible = false, active = true;
    }

    public class Request {
        public Id recordId;
        public String productCode;
        public String determinantKey;       // firm segment (A/N/G); null -> Non-AmLaw cascade
        public Decimal contractYearIndex;
        public String frequencyCode;        // "" | M | Q | H
        public String teamSignal;           // owning sales team (Non-AmLaw !SGRP / !SREN split)
        public String campaignSignal;       // campaign / outreach type (Non-AmLaw !MCLG)
        public String oppType;              // Opportunity Type — gates type-scoped team overrides
        public String repSignal;            // benefitting-group rep (Charlie/Caitlin -> !EMEA+BE, Joey -> !APAC+BA)
        public Boolean isMidMarketPro = false; // deal contains a Mid Market Pro Bundle line -> +Z
        public String currencyCode;         // line currency — qualifies currency-keyed product bases (PCEM|USD -> PCE01)
        public Datetime lineCreatedDate;    // record CreatedDate — grandfathering gate for the dispatch backstop (only NEW lines are enforced)
        public String currentPromo;
        public String currentDispatch;
    }

    public class Result {
        public Id recordId;
        public Boolean inScope = false;
        public Boolean writePromo = false;
        public String promoToWrite;
        public Boolean writeDispatch = false;
        public String dispatchToWrite;
        public String skipReason;
        public Boolean missingPromo = false;    // backstop: promo-applicable line still blank after the engine
        public Boolean missingDispatch = false; // backstop: dispatch-required line still blank after the engine
    }

    public class ApplyOutcome {
        public List<SObject> updates = new List<SObject>();
        public List<String> notes = new List<String>();
        public Integer missingCount = 0;             // in-scope ALM lines still missing a required code
        public List<String> gaps = new List<String>(); // product + which code, for the Custom Error message
    }

    // ====================================================================
    // small utilities
    // ====================================================================
    static Map<Id, List<OpportunityLineItem>> groupOlis(List<OpportunityLineItem> olis) {
        Map<Id, List<OpportunityLineItem>> m = new Map<Id, List<OpportunityLineItem>>();
        for (OpportunityLineItem o : olis) {
            if (!m.containsKey(o.OpportunityId)) m.put(o.OpportunityId, new List<OpportunityLineItem>());
            m.get(o.OpportunityId).add(o);
        }
        return m;
    }

    static List<FlowResult> ordered(List<Id> ids, Map<Id, FlowResult> byId) {
        List<FlowResult> out = new List<FlowResult>();
        for (Id i : ids) out.add(byId.get(i));
        return out;
    }

    static Set<String> splitCsv(String v) {
        Set<String> out = new Set<String>();
        if (String.isBlank(v)) return out;
        for (String p : v.split(';')) {
            String t = p.trim();
            if (t != '') out.add(t);
        }
        return out;
    }

    static String str(Object o) { return o == null ? null : String.valueOf(o); }
    static String blankToEmpty(String s) { return s == null ? '' : s; }
    static String append(String base, String add) { return String.isBlank(base) ? add : base + '; ' + add; }

    static String summarise(List<String> notes, Id ctx) {
        if (notes == null || notes.isEmpty()) return null;
        String msg = 'REV-60 visibility on ' + ctx + ': ' + String.join(notes, ' | ');
        return msg.length() > 255 ? msg.substring(0, 255) : msg;
    }

    /** Backstop message for the save-time Custom Error — lists the in-scope ALM lines still missing a
        required code after the engine ran, plus a config-driven hint naming the valid dispatch codes
        (UAT round 1: a tester typed the product code into Dispatch to clear the block — tell them what
        goes there instead). Null when there is no genuine gap (the normal case). */
    @TestVisible
    static String gapSummary(ApplyOutcome o, EngineConfig cfg) {
        if (o == null || o.missingCount == 0) return null;
        String msg = o.missingCount + ' ALM line(s) still need a required code: ' + String.join(o.gaps, ', ');
        if (cfg != null && String.isNotBlank(cfg.dispatchBackstopHint) && msg.contains('dispatch')) {
            msg += '. ' + cfg.dispatchBackstopHint;
        }
        return msg.length() > 500 ? msg.substring(0, 500) : msg;
    }

    /** Fail-open fault log to Flow_Log__c — the same destination PFC_Log_Fault writes to — so the
        trigger flows stay trivial (no result-reading) and faults are still visible/queryable.
        Logging must never break the engine, hence the swallowed inner catch. */
    @TestVisible
    static void logFault(String context, String errorDescription, String recordName) {
        try {
            insert new Flow_Log__c(
                Class_Name__c = context,
                Error_Description__c = (errorDescription != null && errorDescription.length() > 255) ? errorDescription.substring(0, 255) : errorDescription,
                Flow_Name__c = 'ALMPromoDispatchEngine',
                Record_Name__c = recordName
            );
        } catch (Exception ignore) { /* logging never breaks the engine */ }
    }
}
