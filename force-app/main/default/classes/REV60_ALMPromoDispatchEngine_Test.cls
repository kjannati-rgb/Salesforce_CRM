/**
 * REV-60 — regression tests for the ALM Promo & Dispatch code engine.
 *
 * Two tiers:
 *  1. PURE-LOGIC (no DML, no CMDT, no CPQ): drive derive()/helpers with injected
 *     EngineConfig — exhaustively covers composition (base + Y2/Y3/Y4 + Z), the
 *     additive write-when-blank-or-ALM-owned guard, the strip-to-base rule, and the
 *     never-P* / out-of-scope guardrails. This is the regression matrix.
 *  2. INTEGRATION (injected active config + real records): covers the layer runners'
 *     SOQL/DML and the primary-quote OLI reconciliation. Uses the org-standard bypass
 *     (Application_Settings__c) to silence foreign automation during data creation,
 *     exactly as REV71_ALMCodeFlow_Test does.
 *
 * The deployed engine ships INERT (CMDT switches OFF); the invocable inert-path test
 * proves that, while the injected-config tests prove the logic independently of org state.
 */
@isTest
private class REV60_ALMPromoDispatchEngine_Test {

    // ---------- builders ----------
    static ALMPromoDispatchEngine.EngineConfig baseCfg() {
        ALMPromoDispatchEngine.EngineConfig c = new ALMPromoDispatchEngine.EngineConfig();
        c.masterActive = true; c.layer1Active = true; c.layer2Active = true;
        c.yearSuffixEnabled = true;
        c.almProductCodes = new Set<String>{ 'LAWM' };
        c.segmentPromoProducts = new Set<String>{ 'LAWM' }; // LAWM uses the firm-segment promo cascade
        c.addEntry(entry('LAWM', '!TEST', 'ON', true, false));
        return c;
    }

    /** Integration config: the runners resolve the determinant from the firm segment (null in
        these lightweight tests, so the line falls to the Non-AmLaw cascade). Add a default base
        and a product dispatch so the active path still stamps without standing up a firm hierarchy. */
    static ALMPromoDispatchEngine.EngineConfig intCfg() {
        ALMPromoDispatchEngine.EngineConfig c = baseCfg();
        c.defaultBase = '!TEST';
        c.dispatchByProduct.put('LAWM', 'ON');
        c.yearFieldApi = 'SBQQ__SubscriptionTerm__c';      // mirror the deployed Control so the runners read term/freq
        c.frequencyFieldApi = 'SBQQ__BillingFrequency__c';
        return c;
    }

    static ALMPromoDispatchEngine.MapEntry entry(String key, String base, String disp, Boolean yr, Boolean z) {
        ALMPromoDispatchEngine.MapEntry e = new ALMPromoDispatchEngine.MapEntry();
        e.matchKey = key; e.basePromo = base; e.dispatchCode = disp; e.applyYearSuffix = yr; e.zEligible = z; e.active = true;
        return e;
    }

    static ALMPromoDispatchEngine.Request req(String product, Decimal year, String promo, String dispatch) {
        ALMPromoDispatchEngine.Request r = new ALMPromoDispatchEngine.Request();
        r.recordId = null; r.productCode = product; r.determinantKey = product;
        r.contractYearIndex = year; r.currentPromo = promo; r.currentDispatch = dispatch;
        return r;
    }

    // =====================================================================
    // TIER 1 — pure logic
    // =====================================================================
    @isTest
    static void scopeGate_outOfScope_noWrites() {
        ALMPromoDispatchEngine.Result r = ALMPromoDispatchEngine.derive(baseCfg(), req('XYZ', 1, null, null));
        Assert.isFalse(r.inScope, 'non-ALM product must be out of scope');
        Assert.isFalse(r.writePromo, 'no promo write off-scope');
        Assert.isFalse(r.writeDispatch, 'no dispatch write off-scope');
    }

    @isTest
    static void inScope_noMapping_isFlaggedNotWritten() {
        ALMPromoDispatchEngine.EngineConfig c = baseCfg();
        ALMPromoDispatchEngine.Request rq = req('LAWM', 1, null, null);
        rq.determinantKey = 'UNMAPPED';
        ALMPromoDispatchEngine.Result r = ALMPromoDispatchEngine.derive(c, rq);
        Assert.isTrue(r.inScope, 'ALM product is in scope');
        Assert.isFalse(r.writePromo, 'no mapping -> no promo');
        Assert.isTrue(r.skipReason != null && r.skipReason.contains('No base'), 'unmapped in-scope line is flagged');
    }

    @isTest
    static void blankLine_year1_writesBaseAndDispatch() {
        ALMPromoDispatchEngine.Result r = ALMPromoDispatchEngine.derive(baseCfg(), req('LAWM', 1, null, null));
        Assert.isTrue(r.writePromo, 'blank promo filled');
        Assert.areEqual('!TEST', r.promoToWrite, 'year 1 is unsuffixed');
        Assert.isTrue(r.writeDispatch, 'blank dispatch filled');
        Assert.areEqual('ON', r.dispatchToWrite, 'dispatch standardised to mapped code');
    }

    @isTest
    static void yearSuffix_2_3_4() {
        Assert.areEqual('!TESTY2', ALMPromoDispatchEngine.derive(baseCfg(), req('LAWM', 2, null, null)).promoToWrite);
        Assert.areEqual('!TESTY3', ALMPromoDispatchEngine.derive(baseCfg(), req('LAWM', 3, null, null)).promoToWrite);
        Assert.areEqual('!TESTY4', ALMPromoDispatchEngine.derive(baseCfg(), req('LAWM', 4, null, null)).promoToWrite);
    }

    @isTest
    static void yearSuffix_disabledGlobally_or_perRow() {
        ALMPromoDispatchEngine.EngineConfig g = baseCfg();
        g.yearSuffixEnabled = false;
        Assert.areEqual('!TEST', ALMPromoDispatchEngine.derive(g, req('LAWM', 3, null, null)).promoToWrite, 'global toggle off -> no suffix');

        ALMPromoDispatchEngine.EngineConfig p = baseCfg();
        p.byKey.get('LAWM').applyYearSuffix = false;
        Assert.areEqual('!TEST', ALMPromoDispatchEngine.derive(p, req('LAWM', 3, null, null)).promoToWrite, 'per-row toggle off -> no suffix');
    }

    @isTest
    static void modifier_preservesRepZ_neverInvents() {
        ALMPromoDispatchEngine.EngineConfig c = baseCfg();
        // Z is never invented — a blank line composes with no Z even on a 3-year deal.
        Assert.areEqual('!TESTY3', ALMPromoDispatchEngine.derive(c, req('LAWM', 3, null, null)).promoToWrite, 'engine never invents Z');
        // A rep's trailing Z is PRESERVED when the base/year is refreshed (never stripped).
        ALMPromoDispatchEngine.Result kept = ALMPromoDispatchEngine.derive(c, req('LAWM', 3, '!TESTY2Z', null));
        Assert.isTrue(kept.writePromo, 'ALM-owned code carrying a rep +Z is refreshed');
        Assert.areEqual('!TESTY3Z', kept.promoToWrite, 'year refreshed to Y3, the rep +Z preserved');
        // An already-correct Z code is a no-op.
        Assert.isFalse(ALMPromoDispatchEngine.derive(c, req('LAWM', 3, '!TESTY3Z', null)).writePromo, 'correct Z code untouched');
    }

    @isTest
    static void productBase_andSegmentApplicability() {
        ALMPromoDispatchEngine.EngineConfig c = baseCfg();
        c.segmentPromoProducts = new Set<String>{ 'LAWM', 'LWKM' };
        c.almProductCodes.addAll(new Set<String>{ 'LWKM', 'GLBM', 'NYLM' });
        c.productBase.put('GLBM', 'MSHP');
        c.dispatchByProduct.put('GLBM', 'ME');
        c.byKey.put('A', entry('A', '!AMLW', null, true, false));

        // GLBM uses its product-fixed base MSHP, NOT the firm segment (even on an AmLaw firm)
        ALMPromoDispatchEngine.Request glbm = req('GLBM', 2, null, null);
        glbm.determinantKey = 'A';
        ALMPromoDispatchEngine.Result rg = ALMPromoDispatchEngine.derive(c, glbm);
        Assert.areEqual('MSHPY2', rg.promoToWrite, 'GLBM -> product-fixed MSHP (+year), not the segment base');
        Assert.areEqual('ME', rg.dispatchToWrite, 'GLBM dispatch ME');

        // NYLM is print/online -> NO promo derivation (dispatch-only), and not flagged as a gap
        ALMPromoDispatchEngine.Request nyl = req('NYLM', 3, null, null);
        nyl.determinantKey = 'A';
        ALMPromoDispatchEngine.Result rn = ALMPromoDispatchEngine.derive(c, nyl);
        Assert.isFalse(rn.writePromo, 'NYLM gets no promo (not a segment-promo product)');
        Assert.isNull(rn.skipReason, 'dispatch-only product is not flagged as a missing-base gap');

        // LWKM is a Law.com umbrella product -> segment cascade applies (AmLaw -> !AMLW)
        ALMPromoDispatchEngine.Request lw = req('LWKM', 1, null, null);
        lw.determinantKey = 'A';
        Assert.areEqual('!AMLW', ALMPromoDispatchEngine.derive(c, lw).promoToWrite, 'LWKM uses the firm-segment base');
    }

    @isTest
    static void promoGuard_idempotent_almOwned_legacy() {
        ALMPromoDispatchEngine.EngineConfig c = baseCfg();
        // already correct -> no write
        Assert.isFalse(ALMPromoDispatchEngine.derive(c, req('LAWM', 1, '!TEST', null)).writePromo, 'idempotent: equal value not rewritten');
        // ALM-owned (stripped base matches a configured base) -> refresh allowed
        ALMPromoDispatchEngine.Result owned = ALMPromoDispatchEngine.derive(c, req('LAWM', 1, '!TESTY2', null));
        Assert.isTrue(owned.writePromo, 'ALM-owned prior output may be refreshed');
        Assert.areEqual('!TEST', owned.promoToWrite);
        // legacy LBR value -> never touched
        Assert.isFalse(ALMPromoDispatchEngine.derive(c, req('LAWM', 1, 'MCLG99', null)).writePromo, 'legacy value must never be overwritten');
    }

    @isTest
    static void dispatch_writeOnBlankOnly_neverOverwrites() {
        ALMPromoDispatchEngine.EngineConfig c = baseCfg(); // entry dispatch = 'ON'
        // blank -> filled with the product's deterministic code
        ALMPromoDispatchEngine.Result fill = ALMPromoDispatchEngine.derive(c, req('LAWM', 1, null, null));
        Assert.isTrue(fill.writeDispatch, 'blank dispatch filled');
        Assert.areEqual('ON', fill.dispatchToWrite, 'filled with the deterministic product code');
        // idempotent
        Assert.isFalse(ALMPromoDispatchEngine.derive(c, req('LAWM', 1, '!TEST', 'ON')).writeDispatch, 'equal dispatch not rewritten');
        // a rep's OS/OE/OL is NEVER overwritten (no derivable seat rule — Brady 30 Jun)
        Assert.isFalse(ALMPromoDispatchEngine.derive(c, req('LAWM', 1, '!TEST', 'OE')).writeDispatch, 'rep-set OE never overwritten');
        Assert.isFalse(ALMPromoDispatchEngine.derive(c, req('LAWM', 1, '!TEST', 'OS')).writeDispatch, 'rep-set OS never overwritten');
        // legacy dispatch -> untouched
        Assert.isFalse(ALMPromoDispatchEngine.derive(c, req('LAWM', 1, '!TEST', 'PNU01')).writeDispatch, 'legacy dispatch never overwritten');

        // a configured PRINT code (NYLM -> PO) is legitimately written onto a blank line
        ALMPromoDispatchEngine.EngineConfig nyl = baseCfg();
        nyl.almProductCodes.add('NYLM');
        nyl.dispatchByProduct.put('NYLM', 'PO');
        ALMPromoDispatchEngine.Result po = ALMPromoDispatchEngine.derive(nyl, req('NYLM', 1, null, null));
        Assert.isTrue(po.writeDispatch, 'NYLM dispatch PO written on a blank line');
        Assert.areEqual('PO', po.dispatchToWrite, 'PO is a valid ALM dispatch for NYLM');
    }

    @isTest
    static void almOwned_prefixMatch_handlesFreqYearModifierAndTrickyBases() {
        ALMPromoDispatchEngine.EngineConfig c = baseCfg();
        c.allBases.add('!SJSI'); c.allBases.add('MSHP'); c.allBases.add('!SGRP');
        // base + freq + year + modifier, in any valid combination -> ALM-owned
        Assert.isTrue(ALMPromoDispatchEngine.isAlmOwnedPromo(c, '!SJSIQY3Z'), 'base+Q+Y3+Z is ALM-owned');
        Assert.isTrue(ALMPromoDispatchEngine.isAlmOwnedPromo(c, '!SJSIY5'),   'Y5 recognised');
        Assert.isTrue(ALMPromoDispatchEngine.isAlmOwnedPromo(c, '!SJSI'),     'bare base recognised');
        // bases that END in a freq/modifier letter must NOT be mangled (the prefix-match guard)
        Assert.isTrue(ALMPromoDispatchEngine.isAlmOwnedPromo(c, 'MSHP'),   'base ending in P recognised');
        Assert.isTrue(ALMPromoDispatchEngine.isAlmOwnedPromo(c, '!SGRPQ'), 'base !SGRP + Q recognised');
        // legacy / malformed -> never ALM-owned
        Assert.isFalse(ALMPromoDispatchEngine.isAlmOwnedPromo(c, 'MCLG99'),  'legacy value not ALM-owned');
        Assert.isFalse(ALMPromoDispatchEngine.isAlmOwnedPromo(c, '!SJSIXX'), 'invalid suffix not ALM-owned');
        // suffix validator + frequency mapping
        Assert.isTrue(ALMPromoDispatchEngine.isValidSuffix('QY3Z'));
        Assert.isTrue(ALMPromoDispatchEngine.isValidSuffix(''));
        Assert.isFalse(ALMPromoDispatchEngine.isValidSuffix('XX'));
        Assert.areEqual('M', ALMPromoDispatchEngine.freqCode('Monthly'));
        Assert.areEqual('Q', ALMPromoDispatchEngine.freqCode('Quarterly'));
        Assert.areEqual('H', ALMPromoDispatchEngine.freqCode('Semi-Annual'));
        Assert.areEqual('', ALMPromoDispatchEngine.freqCode('Annual'));
    }

    @isTest
    static void frequency_M_Q_H_composeBeforeYear() {
        ALMPromoDispatchEngine.EngineConfig c = baseCfg();
        ALMPromoDispatchEngine.Request m = req('LAWM', 2, null, null); m.frequencyCode = 'M';
        Assert.areEqual('!TESTMY2', ALMPromoDispatchEngine.derive(c, m).promoToWrite, 'monthly: base+M+Y2');
        ALMPromoDispatchEngine.Request q = req('LAWM', 3, null, null); q.frequencyCode = 'Q';
        Assert.areEqual('!TESTQY3', ALMPromoDispatchEngine.derive(c, q).promoToWrite, 'quarterly: base+Q+Y3');
        ALMPromoDispatchEngine.Request h = req('LAWM', 1, null, null); h.frequencyCode = 'H';
        Assert.areEqual('!TESTH', ALMPromoDispatchEngine.derive(c, h).promoToWrite, 'semi-annual year 1: base+H');
    }

    @isTest
    static void yearSuffix_Y5() {
        Assert.areEqual('!TESTY5', ALMPromoDispatchEngine.derive(baseCfg(), req('LAWM', 5, null, null)).promoToWrite, 'year 5 -> Y5');
    }

    @isTest
    static void defaultBase_usedForUnmappedInScopeLine() {
        ALMPromoDispatchEngine.EngineConfig c = baseCfg();
        c.defaultBase = '!SJSI';                  // the "else Non-AmLaw" fallback
        ALMPromoDispatchEngine.Request rq = req('LAWM', 3, null, null);
        rq.determinantKey = 'UNRANKED';           // no segment row matches
        ALMPromoDispatchEngine.Result r = ALMPromoDispatchEngine.derive(c, rq);
        Assert.isTrue(r.writePromo, 'unmapped in-scope line uses the default base');
        Assert.areEqual('!SJSIY3', r.promoToWrite, 'default base + year');
        Assert.isFalse(r.writeDispatch, 'no dispatch without a real product mapping');
    }

    @isTest
    static void nonAmLaw_overrideCascade_defaultThenTeamThenCampaign() {
        ALMPromoDispatchEngine.EngineConfig c = baseCfg();
        c.defaultBase = '!SJSI';
        c.teamOverrides.put('ShawnTeam', '!SGRP');
        c.campaignOverrides.put('RenewalNotice', '!SREN');
        c.campaignOverrides.put('LegacyCampaign', '!MCLG');

        // Non-AmLaw (no segment row) + no signals -> default !SJSI
        ALMPromoDispatchEngine.Request d = req('LAWM', 1, null, null); d.determinantKey = 'O';
        Assert.areEqual('!SJSI', ALMPromoDispatchEngine.derive(c, d).promoToWrite, 'Non-AmLaw default');

        // team signal -> !SGRP (composes with year)
        ALMPromoDispatchEngine.Request t = req('LAWM', 3, null, null); t.determinantKey = 'O'; t.teamSignal = 'ShawnTeam';
        Assert.areEqual('!SGRPY3', ALMPromoDispatchEngine.derive(c, t).promoToWrite, 'team override -> !SGRP');

        // campaign signal beats team (priority)
        ALMPromoDispatchEngine.Request cm = req('LAWM', 1, null, null);
        cm.determinantKey = 'O'; cm.teamSignal = 'ShawnTeam'; cm.campaignSignal = 'RenewalNotice';
        Assert.areEqual('!SREN', ALMPromoDispatchEngine.derive(c, cm).promoToWrite, 'campaign override wins over team');

        // ranked segment ignores Non-AmLaw overrides entirely
        ALMPromoDispatchEngine.EngineConfig rc = baseCfg();
        rc.byKey.put('A', entry('A', '!AMLW', 'ON', true, false));
        ALMPromoDispatchEngine.Request a = req('LAWM', 2, null, null); a.determinantKey = 'A'; a.teamSignal = 'ShawnTeam';
        Assert.areEqual('!AMLWY2', ALMPromoDispatchEngine.derive(rc, a).promoToWrite, 'ranked segment ignores overrides');
    }

    @isTest
    static void teamOverride_oppTypeGated_wnsRenewalOnly() {
        ALMPromoDispatchEngine.EngineConfig c = baseCfg();
        c.defaultBase = '!SJSI';
        c.teamOverrides.put('Sales Executive WNS', '!SREN');
        c.teamOverrideTypes.put('Sales Executive WNS', new Set<String>{ 'Renewal', 'Upsell' });

        // WNS + Renewal -> !SREN
        ALMPromoDispatchEngine.Request ren = req('LAWM', 1, null, null);
        ren.determinantKey = null; ren.teamSignal = 'Sales Executive WNS'; ren.oppType = 'Renewal';
        Assert.areEqual('!SREN', ALMPromoDispatchEngine.derive(c, ren).promoToWrite, 'WNS + Renewal -> !SREN');

        // WNS + Upsell -> !SREN
        ALMPromoDispatchEngine.Request up = req('LAWM', 3, null, null);
        up.determinantKey = null; up.teamSignal = 'Sales Executive WNS'; up.oppType = 'Upsell';
        Assert.areEqual('!SRENY3', ALMPromoDispatchEngine.derive(c, up).promoToWrite, 'WNS + Upsell -> !SREN (composed)');

        // WNS + New Business -> the type filter excludes it -> default !SJSI
        ALMPromoDispatchEngine.Request nb = req('LAWM', 1, null, null);
        nb.determinantKey = null; nb.teamSignal = 'Sales Executive WNS'; nb.oppType = 'New Business';
        Assert.areEqual('!SJSI', ALMPromoDispatchEngine.derive(c, nb).promoToWrite, 'WNS + New Business -> gated out -> !SJSI');

        // a team override with NO type filter applies on any type (Shawn's !SGRP behaviour)
        ALMPromoDispatchEngine.EngineConfig s = baseCfg();
        s.defaultBase = '!SJSI';
        s.teamOverrides.put('ShawnTeam', '!SGRP'); // no teamOverrideTypes entry -> any
        ALMPromoDispatchEngine.Request sh = req('LAWM', 1, null, null);
        sh.determinantKey = null; sh.teamSignal = 'ShawnTeam'; sh.oppType = 'New Business';
        Assert.areEqual('!SGRP', ALMPromoDispatchEngine.derive(s, sh).promoToWrite, 'unfiltered team override applies on any type');
    }

    @isTest
    static void teamOverride_blankOnly_defaultsButRespectsRepChoice() {
        ALMPromoDispatchEngine.EngineConfig c = baseCfg();
        c.defaultBase = '!SJSI';
        c.teamOverrides.put('Sales Executive WNS', '!SREN');
        c.teamOverrideTypes.put('Sales Executive WNS', new Set<String>{ 'Renewal', 'Upsell' });
        c.teamOverrideBlankOnly.add('Sales Executive WNS'); // !SREN is a default, not a determinant

        // blank WNS renewal -> fill the !SREN default
        ALMPromoDispatchEngine.Request blank = req('LAWM', 1, null, null);
        blank.determinantKey = null; blank.teamSignal = 'Sales Executive WNS'; blank.oppType = 'Renewal';
        Assert.areEqual('!SREN', ALMPromoDispatchEngine.derive(c, blank).promoToWrite, 'blank WNS renewal -> !SREN default');

        // rep deliberately set !SJSI on a WNS renewal -> blank-only override must NOT overwrite it
        ALMPromoDispatchEngine.Request chose = req('LAWM', 1, '!SJSI', null);
        chose.determinantKey = null; chose.teamSignal = 'Sales Executive WNS'; chose.oppType = 'Renewal';
        Assert.isFalse(ALMPromoDispatchEngine.derive(c, chose).writePromo, 'blank-only never overwrites a rep-set !SJSI');

        // rep kept !SREN -> also left alone
        ALMPromoDispatchEngine.Request kept = req('LAWM', 1, '!SREN', null);
        kept.determinantKey = null; kept.teamSignal = 'Sales Executive WNS'; kept.oppType = 'Renewal';
        Assert.isFalse(ALMPromoDispatchEngine.derive(c, kept).writePromo, 'blank-only leaves a rep-set !SREN');
    }

    @isTest
    static void dispatchByProduct_takesPrecedenceOverEntry() {
        ALMPromoDispatchEngine.EngineConfig c = baseCfg();
        c.dispatchByProduct.put('LAWM', 'OE');
        ALMPromoDispatchEngine.Result r = ALMPromoDispatchEngine.derive(c, req('LAWM', 1, null, null));
        Assert.areEqual('OE', r.dispatchToWrite, 'product-keyed dispatch overrides the determinant-entry code');
    }

    @isTest
    static void backstop_flagsGenuineGapsOnlyForRequiredCodes() {
        // engine fills both -> no gap
        ALMPromoDispatchEngine.EngineConfig c = baseCfg();
        c.dispatchRequiredProducts = new Set<String>{ 'LAWM' };
        ALMPromoDispatchEngine.Result ok = ALMPromoDispatchEngine.derive(c, req('LAWM', 1, null, null));
        Assert.isFalse(ok.missingPromo, 'promo filled -> no promo gap');
        Assert.isFalse(ok.missingDispatch, 'dispatch filled -> no dispatch gap');

        // rep-required dispatch the engine cannot derive (no product/entry dispatch) stays blank -> gap
        ALMPromoDispatchEngine.EngineConfig nd = baseCfg();
        nd.dispatchRequiredProducts = new Set<String>{ 'LAWM' };
        nd.byKey.get('LAWM').dispatchCode = null;
        ALMPromoDispatchEngine.Result gap = ALMPromoDispatchEngine.derive(nd, req('LAWM', 1, null, null));
        Assert.isFalse(gap.writeDispatch, 'nothing to fill');
        Assert.isTrue(gap.missingDispatch, 'rep-required dispatch left blank -> gap');

        // a product NOT in dispatchRequiredProducts never flags a dispatch gap
        ALMPromoDispatchEngine.EngineConfig c2 = baseCfg();
        c2.byKey.get('LAWM').dispatchCode = null; // dispatchRequiredProducts empty by default
        Assert.isFalse(ALMPromoDispatchEngine.derive(c2, req('LAWM', 1, null, null)).missingDispatch, 'not required -> no dispatch gap');

        // print/online (no promo, not dispatch-required here) is never a gap
        ALMPromoDispatchEngine.EngineConfig pc = baseCfg();
        pc.almProductCodes.add('NYLM'); // in scope, but not segment-promo and not dispatch-required
        ALMPromoDispatchEngine.Result nyl = ALMPromoDispatchEngine.derive(pc, req('NYLM', 1, null, null));
        Assert.isFalse(nyl.missingPromo, 'dispatch-only product never flags a promo gap');
        Assert.isFalse(nyl.missingDispatch, 'NYLM not dispatch-required here -> no gap');
    }

    @isTest
    static void dispatchBackstop_grandfathersLinesCreatedBeforeCutoff() {
        // POST-GO-LIVE HARDENING (17 Jul). LAWM/LWKM/NYOM were pulled from Dispatch_Required on the
        // go-live night because re-arming them retroactively hard-blocked ~914 legacy open quotes whose
        // rep-entered dispatch is blank (Law.com dispatch is NOT derivable — Brady: no seat thresholds).
        // The cutoff makes the backstop bite on genuinely NEW lines only, so the rule can be re-armed.
        ALMPromoDispatchEngine.EngineConfig c = baseCfg();
        c.dispatchRequiredProducts = new Set<String>{ 'LAWM' };
        c.byKey.get('LAWM').dispatchCode = null;   // rep-entered: the engine has nothing to fill
        c.enforceDispatchAfter = Datetime.newInstanceGmt(2026, 7, 17, 20, 15, 0);

        // a legacy line -> grandfathered, never blocks the save
        ALMPromoDispatchEngine.Request legacy = req('LAWM', 1, '!TEST', null);
        legacy.lineCreatedDate = Datetime.newInstanceGmt(2026, 5, 1, 9, 0, 0);
        Assert.isFalse(ALMPromoDispatchEngine.derive(c, legacy).missingDispatch, 'pre-cutoff line is grandfathered');
        Assert.isFalse(ALMPromoDispatchEngine.dispatchEnforceable(c, legacy), 'gate: pre-cutoff not enforceable');

        // a genuinely new line -> enforced
        ALMPromoDispatchEngine.Request fresh = req('LAWM', 1, '!TEST', null);
        fresh.lineCreatedDate = Datetime.newInstanceGmt(2026, 7, 18, 9, 0, 0);
        Assert.isTrue(ALMPromoDispatchEngine.derive(c, fresh).missingDispatch, 'post-cutoff line is enforced');
        Assert.isTrue(ALMPromoDispatchEngine.dispatchEnforceable(c, fresh), 'gate: post-cutoff enforceable');

        // the boundary is inclusive (>=), so a line created exactly on the cutoff is enforced
        ALMPromoDispatchEngine.Request onDot = req('LAWM', 1, '!TEST', null);
        onDot.lineCreatedDate = c.enforceDispatchAfter;
        Assert.isTrue(ALMPromoDispatchEngine.derive(c, onDot).missingDispatch, 'cutoff boundary is inclusive');

        // undatable line (CreatedDate absent from the query / never persisted) -> grandfathered.
        // The backstop must never hard-block a line it cannot positively date.
        ALMPromoDispatchEngine.Request undated = req('LAWM', 1, '!TEST', null);
        Assert.isFalse(ALMPromoDispatchEngine.derive(c, undated).missingDispatch, 'undatable line is grandfathered');

        // NO cutoff configured -> unchanged original behaviour, enforce on every line regardless of age.
        // This is what keeps the always-on GLBM/NYLM enforcement (and every pre-existing test) intact.
        ALMPromoDispatchEngine.EngineConfig always = baseCfg();
        always.dispatchRequiredProducts = new Set<String>{ 'LAWM' };
        always.byKey.get('LAWM').dispatchCode = null;
        ALMPromoDispatchEngine.Request oldNoCutoff = req('LAWM', 1, '!TEST', null);
        oldNoCutoff.lineCreatedDate = Datetime.newInstanceGmt(2026, 5, 1, 9, 0, 0);
        Assert.isTrue(ALMPromoDispatchEngine.derive(always, oldNoCutoff).missingDispatch, 'null cutoff -> enforce always');

        // the cutoff gates the BACKSTOP ONLY — it must not suppress the engine's own writes. A legacy
        // line of a deterministic-dispatch product still self-heals (NYLM -> PO) exactly as before.
        ALMPromoDispatchEngine.EngineConfig det = baseCfg();
        det.almProductCodes.add('NYLM');
        det.dispatchRequiredProducts = new Set<String>{ 'NYLM' };
        det.dispatchByProduct.put('NYLM', 'PO');
        det.enforceDispatchAfter = Datetime.newInstanceGmt(2026, 7, 17, 20, 15, 0);
        ALMPromoDispatchEngine.Request oldNyl = req('NYLM', 1, null, null);
        oldNyl.lineCreatedDate = Datetime.newInstanceGmt(2026, 5, 1, 9, 0, 0);
        ALMPromoDispatchEngine.Result rn = ALMPromoDispatchEngine.derive(det, oldNyl);
        Assert.isTrue(rn.writeDispatch, 'legacy NYLM line still auto-fills its deterministic PO');
        Assert.isFalse(rn.missingDispatch, 'and therefore self-heals to no gap');
    }

    @isTest
    static void logFault_writesFlowLogFailOpen() {
        ALMPromoDispatchEngine.logFault('REV-60 test fault', 'something went wrong', 'q-123');
        List<Flow_Log__c> logs = [SELECT Class_Name__c, Error_Description__c, Flow_Name__c, Record_Name__c
            FROM Flow_Log__c WHERE Class_Name__c = 'REV-60 test fault'];
        Assert.areEqual(1, logs.size(), 'a Flow_Log row is written on fault');
        Assert.areEqual('ALMPromoDispatchEngine', logs[0].Flow_Name__c, 'flow name stamped');
    }

    @isTest
    static void fieldAndContextResolution() {
        ALMPromoDispatchEngine.EngineConfig c = baseCfg();
        c.yearFieldApi = 'SBQQ__SubscriptionTerm__c';
        c.frequencyFieldApi = 'SBQQ__BillingFrequency__c';
        c.teamOverrides.put('Global Enterprise Solutions & Memberships', '!SGRP');

        // year = subscription-term months / 12
        Assert.areEqual(3, ALMPromoDispatchEngine.resolveYearIndex(new SBQQ__QuoteLine__c(SBQQ__SubscriptionTerm__c = 36), c).intValue(), '36 months -> year 3');
        Assert.areEqual(1, ALMPromoDispatchEngine.resolveYearIndex(new SBQQ__QuoteLine__c(SBQQ__SubscriptionTerm__c = 12), c).intValue(), '12 months -> year 1');
        Assert.areEqual(1, ALMPromoDispatchEngine.resolveYearIndex(new SBQQ__QuoteLine__c(), c).intValue(), 'null term -> year 1');

        // frequency off the billing-frequency field
        Assert.areEqual('Q', ALMPromoDispatchEngine.resolveFrequency(new SBQQ__QuoteLine__c(SBQQ__BillingFrequency__c = 'Quarterly'), c), 'Quarterly -> Q');

        // team signal via role.contains()
        Assert.areEqual('Global Enterprise Solutions & Memberships',
            ALMPromoDispatchEngine.resolveTeamSignal('ALM Legal - IS - Global Enterprise Solutions & Memberships - Sales Executive', c),
            'Shawn team role -> matched override key');
        Assert.isNull(ALMPromoDispatchEngine.resolveTeamSignal('ALM Legal - IS - Legal Subscriptions & Customer Retention - Sales Executive', c),
            'other team -> no override');
    }

    @isTest
    static void repOverride_emeaApac_baseAndDispatch() {
        ALMPromoDispatchEngine.EngineConfig c = baseCfg();
        c.defaultBase = '!SJSI';
        c.byKey.get('LAWM').dispatchCode = null; // Law.com dispatch is rep-entered unless a rep override applies
        c.teamOverrides.put('SomeTeam', '!SGRP');
        c.repOverrides.put('Charlie Murray', '!EMEA');
        c.repOverrideDispatch.put('Charlie Murray', 'BE');
        c.repOverrides.put('Joey Kwok', '!APAC');
        c.repOverrideDispatch.put('Joey Kwok', 'BA');

        // EMEA rep, Non-AmLaw, 2yr -> !EMEAY2 (mirrors !SJSI composition) + dispatch BE auto-filled
        ALMPromoDispatchEngine.Request em = req('LAWM', 2, null, null);
        em.determinantKey = null; em.repSignal = 'Charlie Murray';
        ALMPromoDispatchEngine.Result r1 = ALMPromoDispatchEngine.derive(c, em);
        Assert.areEqual('!EMEAY2', r1.promoToWrite, 'EMEA rep -> !EMEA base, composes year');
        Assert.areEqual('BE', r1.dispatchToWrite, 'EMEA rep -> dispatch BE');

        // APAC rep -> !APAC / BA
        ALMPromoDispatchEngine.Request ap = req('LAWM', 1, null, null);
        ap.determinantKey = null; ap.repSignal = 'Joey Kwok';
        ALMPromoDispatchEngine.Result r2 = ALMPromoDispatchEngine.derive(c, ap);
        Assert.areEqual('!APAC', r2.promoToWrite, 'APAC rep -> !APAC');
        Assert.areEqual('BA', r2.dispatchToWrite, 'APAC rep -> dispatch BA');

        // rep override beats a team override (more specific)
        ALMPromoDispatchEngine.Request both = req('LAWM', 1, null, null);
        both.determinantKey = null; both.teamSignal = 'SomeTeam'; both.repSignal = 'Charlie Murray';
        Assert.areEqual('!EMEA', ALMPromoDispatchEngine.derive(c, both).promoToWrite, 'rep override beats team override');

        // rep override BEATS the firm ranking (Finance/Laurie Melzi 16 Jul: "!EMEA/!APAC used
        // regardless of ranking")
        c.byKey.put('A', entry('A', '!AMLW', null, true, false));
        ALMPromoDispatchEngine.Request ranked = req('LAWM', 1, null, null);
        ranked.determinantKey = 'A'; ranked.repSignal = 'Charlie Murray';
        ALMPromoDispatchEngine.Result r3 = ALMPromoDispatchEngine.derive(c, ranked);
        Assert.areEqual('!EMEA', r3.promoToWrite, 'rep override wins even on a ranked firm');
        Assert.areEqual('BE', r3.dispatchToWrite, 'dispatch BE on a ranked firm');

        // ...but a product-fixed base (GLBM/PCGE coding schemes) still wins over the rep override
        c.almProductCodes.add('GLBM');
        c.productBase.put('GLBM', 'MSHP');
        ALMPromoDispatchEngine.Request pb = req('GLBM', 1, null, null);
        pb.determinantKey = null; pb.repSignal = 'Charlie Murray';
        Assert.areEqual('MSHP', ALMPromoDispatchEngine.derive(c, pb).promoToWrite, 'product-fixed base beats the rep override');

        // a rep-set dispatch is never overwritten (write-on-blank-only)
        ALMPromoDispatchEngine.Request kept = req('LAWM', 1, null, 'OE');
        kept.determinantKey = null; kept.repSignal = 'Charlie Murray';
        Assert.isFalse(ALMPromoDispatchEngine.derive(c, kept).writeDispatch, 'rep-set OE never overwritten by BE');

        // rep-signal name matching is exact + case-insensitive
        Assert.areEqual('Charlie Murray', ALMPromoDispatchEngine.resolveRepSignal('charlie murray', c), 'case-insensitive match');
        Assert.isNull(ALMPromoDispatchEngine.resolveRepSignal('Charlie Murrayson', c), 'no partial-name match');
    }

    @isTest
    static void frequency_quoteFirst_lineIsProductDefaultNoise() {
        ALMPromoDispatchEngine.EngineConfig c = baseCfg();
        c.frequencyFieldApi = 'SBQQ__BillingFrequency__c';
        // UAT round 2 (Q-206292/93): quote=Quarterly but CPQ stamps every line 'Annual' from the
        // product default — the quote value must WIN over the line value.
        ALMPromoDispatchEngine.DerivContext ctx = new ALMPromoDispatchEngine.DerivContext();
        ctx.quoteFrequency = 'Quarterly';
        SBQQ__QuoteLine__c ln = new SBQQ__QuoteLine__c(SBQQ__BillingFrequency__c = 'Annual');
        Assert.areEqual('Q', ALMPromoDispatchEngine.resolveFrequency(ln, c, ctx), 'quote Quarterly beats line Annual');
        // no quote-level value -> line value used (Layer 2 / OLI path)
        Assert.areEqual('M', ALMPromoDispatchEngine.resolveFrequency(
            new SBQQ__QuoteLine__c(SBQQ__BillingFrequency__c = 'Monthly'), c, new ALMPromoDispatchEngine.DerivContext()),
            'blank quote frequency falls back to the line');
    }

    @isTest
    static void mmProBundleChildren_areDerived_ordinaryChildrenExcluded() {
        // PROD (16 Jul): Mid Market Pro Bundle CHILD lines carry full promos (!AMLWY3Z etc.) — they
        // are the invoiced subscriptions. Ordinary bundle children stay excluded (parent carries the code).
        ALMPromoDispatchEngine.EngineConfig c = baseCfg();
        c.defaultBase = '!SJSI';
        // generic-FieldSet mock (same pattern as the sibling-scan test): Account stands in for a line
        ALMPromoDispatchEngine.FieldSet fs = new ALMPromoDispatchEngine.FieldSet();
        fs.product = 'Name'; fs.promo = 'Description'; fs.dispatch = 'Site'; fs.child1 = 'ParentId';

        // an MMPro deal: child LAWM line IS derived, with Z
        ALMPromoDispatchEngine.DerivContext mm = new ALMPromoDispatchEngine.DerivContext();
        mm.isMidMarketPro = true; mm.quoteTerm = 36;
        Account child = new Account(Name = 'LAWM', ParentId = '001000000000001AAA');
        ALMPromoDispatchEngine.ApplyOutcome o1 = ALMPromoDispatchEngine.applyToRecords(new List<SObject>{ child }, c, fs, mm);
        Assert.areEqual(1, o1.updates.size(), 'MMPro bundle child is derived');
        Assert.areEqual('!SJSIY3Z', (String) o1.updates[0].get('Description'), 'child gets base + deal-length year + Z');

        // an ordinary deal: the same child line is excluded
        ALMPromoDispatchEngine.DerivContext plain = new ALMPromoDispatchEngine.DerivContext();
        plain.quoteTerm = 36;
        ALMPromoDispatchEngine.ApplyOutcome o2 = ALMPromoDispatchEngine.applyToRecords(new List<SObject>{ child }, c, fs, plain);
        Assert.areEqual(0, o2.updates.size(), 'ordinary bundle child stays excluded');
    }

    @isTest
    static void modifier_zFromMidMarketBundle_andPreserved() {
        // Deal contains a Mid Market Pro Bundle line -> +Z on the deal's ALM lines (PROD: 43/43
        // LAWM lines on bundle quotes carry Z). A rep's typed Z is still preserved without the bundle.
        ALMPromoDispatchEngine.EngineConfig c = baseCfg();
        c.midMarketProProductCodes = new Set<String>{ 'Mid Market Pro Bundle' };

        ALMPromoDispatchEngine.Request mm = req('LAWM', 3, null, null);
        mm.isMidMarketPro = true;
        Assert.areEqual('!TESTY3Z', ALMPromoDispatchEngine.derive(c, mm).promoToWrite, 'bundle on deal -> Z appended');

        Assert.areEqual('!TESTY3', ALMPromoDispatchEngine.derive(c, req('LAWM', 3, null, null)).promoToWrite, 'no bundle, no typed Z -> no Z');

        ALMPromoDispatchEngine.Request typed = req('LAWM', 3, '!TESTY2Z', null);
        Assert.areEqual('!TESTY3Z', ALMPromoDispatchEngine.derive(c, typed).promoToWrite, 'typed Z preserved without the bundle');

        // sibling scan helper
        ALMPromoDispatchEngine.FieldSet fs = new ALMPromoDispatchEngine.FieldSet();
        fs.product = 'Name';
        Assert.isTrue(ALMPromoDispatchEngine.hasMidMarketProduct(
            new List<SObject>{ new Account(Name = 'LAWM'), new Account(Name = 'Mid Market Pro Bundle') }, fs, c), 'bundle sibling detected');
        Assert.isFalse(ALMPromoDispatchEngine.hasMidMarketProduct(
            new List<SObject>{ new Account(Name = 'LAWM') }, fs, c), 'no bundle -> false');
    }

    @isTest
    static void yearIndex_mdqSegments_useDealLength() {
        // SETTLED (UAT round 4, Cindy's Q-206348 + PROD Q-217644/Q-217352): MDQ segmented
        // one-line-per-year quotes carry the DEAL-LENGTH Yn on EVERY segment line (!SJSIY3 on
        // Year 1/2/3 alike) — the org's "multiyear must have Y" validation enforces it. So a
        // segmented line resolves the year exactly like any other line: line term, else quote term.
        ALMPromoDispatchEngine.EngineConfig c = baseCfg();
        c.yearFieldApi = 'SBQQ__SubscriptionTerm__c';
        ALMPromoDispatchEngine.DerivContext ctx = new ALMPromoDispatchEngine.DerivContext();
        ctx.quoteTerm = 36; // 3-year quote
        Assert.areEqual(3, ALMPromoDispatchEngine.resolveYearIndex(new SBQQ__QuoteLine__c(SBQQ__SegmentIndex__c = 1), c, ctx).intValue(), 'year-1 segment still gets the deal-length year (3)');
        Assert.areEqual(3, ALMPromoDispatchEngine.resolveYearIndex(new SBQQ__QuoteLine__c(SBQQ__SegmentIndex__c = 2), c, ctx).intValue(), 'year-2 segment -> deal-length year');
        Assert.areEqual(3, ALMPromoDispatchEngine.resolveYearIndex(new SBQQ__QuoteLine__c(), c, ctx).intValue(), 'plain line -> quote term (36mo -> yr 3)');
        // +Z preserved through a deal-length refresh (E2's actual purpose)
        ALMPromoDispatchEngine.Request r = req('LAWM', 3, '!TESTY2Z', null);
        Assert.areEqual('!TESTY3Z', ALMPromoDispatchEngine.derive(c, r).promoToWrite, 'Y2Z -> Y3Z, Z preserved');
    }

    @isTest
    static void productBase_currencyKeyed_pcgeBare() {
        ALMPromoDispatchEngine.EngineConfig c = baseCfg();
        c.almProductCodes.add('PCEM');
        c.productBase.put('PCEM|USD', 'PCE01');
        c.productBase.put('PCEM|EUR', 'PCE02');
        c.productBase.put('PCEM|GBP', 'PCE03');
        c.productBasePlain.addAll(new Set<String>{ 'PCEM|USD', 'PCEM|EUR', 'PCEM|GBP' });
        c.dispatchByProduct.put('PCEM', 'ME');

        // per-currency base, written BARE — no year/freq suffixes even on a quarterly 3-year deal
        ALMPromoDispatchEngine.Request usd = req('PCEM', 3, null, null);
        usd.determinantKey = null; usd.currencyCode = 'USD'; usd.frequencyCode = 'Q';
        ALMPromoDispatchEngine.Result r1 = ALMPromoDispatchEngine.derive(c, usd);
        Assert.areEqual('PCE01', r1.promoToWrite, 'USD -> PCE01, bare (no QY3)');
        Assert.areEqual('ME', r1.dispatchToWrite, 'PCGE dispatch ME');

        ALMPromoDispatchEngine.Request eur = req('PCEM', 1, null, null);
        eur.determinantKey = null; eur.currencyCode = 'eur'; // case-insensitive
        Assert.areEqual('PCE02', ALMPromoDispatchEngine.derive(c, eur).promoToWrite, 'EUR -> PCE02');

        ALMPromoDispatchEngine.Request gbp = req('PCEM', 1, null, null);
        gbp.determinantKey = null; gbp.currencyCode = 'GBP';
        Assert.areEqual('PCE03', ALMPromoDispatchEngine.derive(c, gbp).promoToWrite, 'GBP -> PCE03');

        // unmapped currency -> no promo (rep-entered), dispatch still fills, no gap flagged
        ALMPromoDispatchEngine.Request aud = req('PCEM', 1, null, null);
        aud.determinantKey = null; aud.currencyCode = 'AUD';
        ALMPromoDispatchEngine.Result r4 = ALMPromoDispatchEngine.derive(c, aud);
        Assert.isFalse(r4.writePromo, 'unmapped currency -> promo stays rep-entered');
        Assert.isFalse(r4.missingPromo, 'not flagged as a gap');
        Assert.areEqual('ME', r4.dispatchToWrite, 'dispatch ME regardless of currency');

        // currency change refresh: an engine-authored PCE01 may be corrected to PCE03
        ALMPromoDispatchEngine.Request chg = req('PCEM', 1, 'PCE01', null);
        chg.determinantKey = null; chg.currencyCode = 'GBP';
        ALMPromoDispatchEngine.Result r5 = ALMPromoDispatchEngine.derive(c, chg);
        Assert.isTrue(r5.writePromo, 'ALM-owned PCE01 refreshable');
        Assert.areEqual('PCE03', r5.promoToWrite, 'currency change corrects the tier');
    }

    @isTest
    static void gapSummary_appendsDispatchHint() {
        ALMPromoDispatchEngine.EngineConfig c = baseCfg();
        c.dispatchBackstopHint = 'Enter ON/OS/OE/OL.';
        ALMPromoDispatchEngine.ApplyOutcome o = new ALMPromoDispatchEngine.ApplyOutcome();
        o.missingCount = 1; o.gaps.add('LAWM (dispatch)');
        String msg = ALMPromoDispatchEngine.gapSummary(o, c);
        Assert.isTrue(msg.contains('LAWM (dispatch)'), 'gap list present');
        Assert.isTrue(msg.contains('Enter ON/OS/OE/OL.'), 'dispatch hint appended');
        // promo-only gap -> no dispatch hint
        ALMPromoDispatchEngine.ApplyOutcome po = new ALMPromoDispatchEngine.ApplyOutcome();
        po.missingCount = 1; po.gaps.add('LAWM (promo)');
        Assert.isFalse(ALMPromoDispatchEngine.gapSummary(po, c).contains('Enter ON'), 'no hint on a promo-only gap');
        // no gap -> null
        Assert.isNull(ALMPromoDispatchEngine.gapSummary(new ALMPromoDispatchEngine.ApplyOutcome(), c), 'no gap -> null');
    }

    @isTest
    static void resolveYearAndFreq_fallBackToQuoteLevel() {
        // REV-60 UAT A2/A3 regression: real CPQ holds term/frequency on the QUOTE; the line is blank.
        ALMPromoDispatchEngine.EngineConfig c = baseCfg();
        c.yearFieldApi = 'SBQQ__SubscriptionTerm__c';
        c.frequencyFieldApi = 'SBQQ__BillingFrequency__c';
        ALMPromoDispatchEngine.DerivContext ctx = new ALMPromoDispatchEngine.DerivContext();
        ctx.quoteTerm = 36;              // 3-year deal at the quote level
        ctx.quoteFrequency = 'Quarterly';

        // blank line -> use the quote-level values
        SBQQ__QuoteLine__c blank = new SBQQ__QuoteLine__c();
        Assert.areEqual(3, ALMPromoDispatchEngine.resolveYearIndex(blank, c, ctx).intValue(), 'blank line term -> quote term (36mo -> yr 3)');
        Assert.areEqual('Q', ALMPromoDispatchEngine.resolveFrequency(blank, c, ctx), 'blank line freq -> quote freq (Quarterly -> Q)');

        // TERM: a line-level value WINS over the quote fallback (multi-sub quotes carry real per-line terms).
        // FREQUENCY: the QUOTE wins — the line value is CPQ product-default noise (UAT round 2).
        SBQQ__QuoteLine__c ovr = new SBQQ__QuoteLine__c(SBQQ__SubscriptionTerm__c = 12, SBQQ__BillingFrequency__c = 'Annual');
        Assert.areEqual(1, ALMPromoDispatchEngine.resolveYearIndex(ovr, c, ctx).intValue(), 'line term overrides the quote fallback');
        Assert.areEqual('Q', ALMPromoDispatchEngine.resolveFrequency(ovr, c, ctx), 'quote frequency beats the line product-default');

        // no ctx -> no fallback (blank line -> year 1 / annual)
        Assert.areEqual(1, ALMPromoDispatchEngine.resolveYearIndex(blank, c).intValue(), 'no ctx -> year 1');
        Assert.areEqual('', ALMPromoDispatchEngine.resolveFrequency(blank, c), 'no ctx -> annual');
    }

    @isTest
    static void writeGuards_directUnit() {
        ALMPromoDispatchEngine.EngineConfig c = baseCfg();
        Assert.isTrue(ALMPromoDispatchEngine.isPromoWritable(c, null, '!TEST'), 'blank promo writable');
        Assert.isFalse(ALMPromoDispatchEngine.isPromoWritable(c, '!TEST', '!TEST'), 'equal promo not writable');
        Assert.isTrue(ALMPromoDispatchEngine.isPromoWritable(c, '!TESTY3', '!TEST'), 'ALM-owned promo writable');
        Assert.isFalse(ALMPromoDispatchEngine.isPromoWritable(c, 'ZZZ', '!TEST'), 'legacy promo not writable');
        Assert.isTrue(ALMPromoDispatchEngine.isDispatchWritable(c, null, 'ON'), 'blank dispatch writable');
        Assert.isFalse(ALMPromoDispatchEngine.isDispatchWritable(c, 'ON', 'ON'), 'equal dispatch not writable');
        Assert.isFalse(ALMPromoDispatchEngine.isDispatchWritable(c, 'PO', 'ON'), 'legacy dispatch not writable');
    }

    // =====================================================================
    // TIER 2 — integration
    // =====================================================================
    @testSetup
    static void setup() {
        // Silence foreign automation during this class's DML (org-standard bypass).
        insert new Application_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Disable_Autolaunch_Lightning_Flow__c = true);
        Product2 p = new Product2(Name = 'Law.com', ProductCode = 'LAWM', IsActive = true,
            Division__c = 'ALM', Reporting_Stream__c = 'Subs - Law.com');
        insert p;
        insert new PricebookEntry(Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = p.Id, UnitPrice = 0, IsActive = true, CurrencyIsoCode = 'USD');
    }

    static Id lawmPbe() {
        return [SELECT Id FROM PricebookEntry WHERE Product2.ProductCode = 'LAWM' LIMIT 1].Id;
    }

    static Opportunity makeOpp() {
        Account a = new Account(Name = 'REV60T Account');
        insert a;
        Opportunity o = new Opportunity(Name = 'REV60T', AccountId = a.Id, StageName = 'Qualify',
            CloseDate = Date.today().addDays(30), CurrencyIsoCode = 'USD',
            Pricebook2Id = Test.getStandardPricebookId());
        insert o;
        return o;
    }

    static SBQQ__Quote__c makeQuote(Opportunity o, Boolean primary) {
        SBQQ__Quote__c q = new SBQQ__Quote__c(SBQQ__Account__c = o.AccountId, SBQQ__Opportunity2__c = o.Id,
            SBQQ__Primary__c = primary, SBQQ__PriceBook__c = Test.getStandardPricebookId(),
            SBQQ__PricebookId__c = Test.getStandardPricebookId(), CurrencyIsoCode = 'USD',
            SBQQ__StartDate__c = Date.today(), SBQQ__SubscriptionTerm__c = 12);
        insert q;
        return q;
    }

    @isTest
    static void loadConfig_readsDeployedControl() {
        // Switch-AGNOSTIC (the engine is live in PROD post-cutover): assert config loads, not its state.
        ALMPromoDispatchEngine.EngineConfig cfg = ALMPromoDispatchEngine.loadConfig();
        Assert.isTrue(cfg.almProductCodes.contains('LAWM'), 'ALM scope set is seeded');
        Assert.isTrue(cfg.byKey.containsKey('A'), 'segment rows are seeded');
    }

    @isTest
    static void invocables_runSafely_andInertPathHolds() {
        // The kill-switch inert path is proven with an INJECTED all-off config (org switches may be ON
        // in a live org); the real invocables are exercised for wrapper coverage and must not throw.
        ALMPromoDispatchEngine.EngineConfig off = new ALMPromoDispatchEngine.EngineConfig(); // all false
        Opportunity o = makeOpp();
        List<ALMPromoDispatchEngine.FlowResult> rOff = ALMPromoDispatchEngine.runLayer2(new List<Id>{ o.Id }, off);
        Assert.isFalse(rOff[0].ran, 'injected all-off config -> Layer 2 inert');
        List<ALMPromoDispatchEngine.FlowResult> rOff1 = ALMPromoDispatchEngine.runLayer1(new List<Id>{ o.Id }, off);
        Assert.isFalse(rOff1[0].ran, 'injected all-off config -> Layer 1 inert');

        // real invocables (live CMDT, whatever state): must return one result per id, no exception
        List<ALMPromoDispatchEngine.FlowResult> r2 = ALMPromoDispatchOppAction.stampOpportunity(new List<Id>{ o.Id });
        Assert.areEqual(1, r2.size(), 'Layer 2 invocable returns a result');
        List<ALMPromoDispatchEngine.FlowResult> r1 = ALMPromoDispatchEngine.stampQuote(new List<Id>{ o.Id });
        Assert.areEqual(1, r1.size(), 'Layer 1 invocable returns a result');
    }

    @isTest
    static void layer2_usesPrimaryQuoteTerm_neverDowngrades() {
        // UAT round 4 B2: a 5-year deal's OLIs were downgraded !AMLWY5 -> !AMLW because Layer 2 had
        // no term source. The primary quote's term/frequency now feed the Layer-2 context.
        ALMPromoDispatchEngine.DerivContext ctx = new ALMPromoDispatchEngine.DerivContext();
        Opportunity opp = new Opportunity(Name = 'x');
        opp.putSObject('SBQQ__PrimaryQuote__r', new SBQQ__Quote__c(SBQQ__SubscriptionTerm__c = 60, SBQQ__BillingFrequency__c = 'Quarterly'));
        ALMPromoDispatchEngine.applyPrimaryQuoteContext(ctx, opp);
        Assert.areEqual(60, ctx.quoteTerm.intValue(), 'primary quote term feeds the OLI context');
        Assert.areEqual('Quarterly', ctx.quoteFrequency, 'primary quote frequency feeds the OLI context');

        // and with that context, an OLI on a 5-year deal composes Y5 (no downgrade of a synced !TESTY5)
        ALMPromoDispatchEngine.EngineConfig c = baseCfg();
        c.yearFieldApi = 'SBQQ__SubscriptionTerm__c';
        ALMPromoDispatchEngine.DerivContext ctx5 = new ALMPromoDispatchEngine.DerivContext();
        ctx5.quoteTerm = 60;
        Assert.areEqual(5, ALMPromoDispatchEngine.resolveYearIndex(new OpportunityLineItem(), c, ctx5).intValue(), 'OLI with no own term -> primary quote term (60mo -> yr 5)');
        ALMPromoDispatchEngine.Request r = req('LAWM', 5, '!TESTY5', null);
        Assert.isFalse(ALMPromoDispatchEngine.derive(c, r).writePromo, '!TESTY5 already correct -> idempotent, no downgrade');

        // no primary quote -> context untouched (fail-safe)
        ALMPromoDispatchEngine.DerivContext ctxN = new ALMPromoDispatchEngine.DerivContext();
        ALMPromoDispatchEngine.applyPrimaryQuoteContext(ctxN, new Opportunity(Name = 'y'));
        Assert.isNull(ctxN.quoteTerm, 'no primary quote -> no term');
    }

    @isTest
    static void layer2_active_stampsBlankAndLeavesLegacy() {
        Opportunity o = makeOpp();
        OpportunityLineItem blankOli = new OpportunityLineItem(OpportunityId = o.Id, PricebookEntryId = lawmPbe(), Quantity = 1, UnitPrice = 100);
        OpportunityLineItem legacyOli = new OpportunityLineItem(OpportunityId = o.Id, PricebookEntryId = lawmPbe(), Quantity = 1, UnitPrice = 100,
            Promo_Code__c = 'LEGACY99', Dispatch_Method_Code__c = 'PNU01');
        insert new List<OpportunityLineItem>{ blankOli, legacyOli };

        Test.startTest();
        ALMPromoDispatchEngine.runLayer2(new List<Id>{ o.Id }, intCfg());
        Test.stopTest();

        Map<Id, OpportunityLineItem> after = new Map<Id, OpportunityLineItem>([
            SELECT Id, Promo_Code__c, Dispatch_Method_Code__c FROM OpportunityLineItem WHERE OpportunityId = :o.Id]);
        Assert.areEqual('!TEST', after.get(blankOli.Id).Promo_Code__c, 'blank OLI promo stamped');
        Assert.areEqual('ON', after.get(blankOli.Id).Dispatch_Method_Code__c, 'blank OLI dispatch stamped');
        Assert.areEqual('LEGACY99', after.get(legacyOli.Id).Promo_Code__c, 'legacy OLI promo untouched');
        Assert.areEqual('PNU01', after.get(legacyOli.Id).Dispatch_Method_Code__c, 'legacy OLI dispatch untouched');
    }

    @isTest
    static void layer1_active_stampsQuoteLines() {
        Product2 p = [SELECT Id FROM Product2 WHERE ProductCode = 'LAWM' LIMIT 1];
        Opportunity o = makeOpp();
        SBQQ__Quote__c q = makeQuote(o, false);
        SBQQ__QuoteLine__c ql = new SBQQ__QuoteLine__c(SBQQ__Quote__c = q.Id, SBQQ__Product__c = p.Id,
            SBQQ__Quantity__c = 1, SBQQ__PricebookEntryId__c = lawmPbe(),
            SBQQ__ListPrice__c = 100, SBQQ__CustomerPrice__c = 100, SBQQ__NetPrice__c = 100, SBQQ__Number__c = 1);
        insert ql;

        Test.startTest();
        ALMPromoDispatchEngine.runLayer1(new List<Id>{ q.Id }, intCfg());
        Test.stopTest();

        SBQQ__QuoteLine__c after = [SELECT SBQQ__ProductCode__c, Promo_Code__c, Dispatch_Method_Code__c
            FROM SBQQ__QuoteLine__c WHERE Id = :ql.Id];
        Assert.areEqual('LAWM', after.SBQQ__ProductCode__c, 'precondition: CPQ stamps ProductCode from the product on insert');
        Assert.areEqual('!TEST', after.Promo_Code__c, 'Layer 1 stamps the quote-line promo');
        Assert.areEqual('ON', after.Dispatch_Method_Code__c, 'Layer 1 stamps the quote-line dispatch');
    }

    @isTest
    static void layer1_readsQuoteLevelTerm_forMultiyear() {
        // REV-60 UAT A2/A3 regression: the term lives on the QUOTE (36mo = 3yr); the line term is blank.
        // The engine must read the quote-level term so the promo gets the Y3 suffix (else the org's
        // "multiyear must have Yn" validation rejects the write and the promo silently stays blank).
        Product2 p = [SELECT Id FROM Product2 WHERE ProductCode = 'LAWM' LIMIT 1];
        Opportunity o = makeOpp();
        SBQQ__Quote__c q = makeQuote(o, false);
        q.SBQQ__SubscriptionTerm__c = 36;    // 3-year at the quote level
        update q;
        SBQQ__QuoteLine__c ql = new SBQQ__QuoteLine__c(SBQQ__Quote__c = q.Id, SBQQ__Product__c = p.Id,
            SBQQ__Quantity__c = 1, SBQQ__PricebookEntryId__c = lawmPbe(),
            SBQQ__ListPrice__c = 100, SBQQ__CustomerPrice__c = 100, SBQQ__NetPrice__c = 100, SBQQ__Number__c = 1);
        insert ql;    // NOTE: no SBQQ__SubscriptionTerm__c on the line

        Test.startTest();
        ALMPromoDispatchEngine.runLayer1(new List<Id>{ q.Id }, intCfg());
        Test.stopTest();

        SBQQ__QuoteLine__c after = [SELECT Promo_Code__c FROM SBQQ__QuoteLine__c WHERE Id = :ql.Id];
        Assert.areEqual('!TESTY3', after.Promo_Code__c, 'quote-level term (36mo) drives the Y3 suffix even with a blank line term');
    }

    @isTest
    static void layer1_primaryQuote_runsReconciliationBranch() {
        // A primary quote routes Layer 1 through the OLI-reconciliation branch. CPQ's
        // managed package owns OLIs on a primary quote, so here we only assert the engine
        // runs the branch cleanly — the OLI write path itself is covered by the Layer 2 test.
        Opportunity o = makeOpp();
        SBQQ__Quote__c q = makeQuote(o, true);
        Test.startTest();
        List<ALMPromoDispatchEngine.FlowResult> r = ALMPromoDispatchEngine.runLayer1(new List<Id>{ q.Id }, intCfg());
        Test.stopTest();
        Assert.isTrue(r[0].ran, 'Layer 1 ran for the primary quote');
        Assert.isNull(r[0].faultMessage, 'no fault on the reconciliation path: ' + r[0].faultMessage);
    }
}
