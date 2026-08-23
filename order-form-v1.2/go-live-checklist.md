# Order Form v1.2 - go-live checklist (as of 2026-08-22)

Build phases 0-5 complete; **full Adobe round trip PROVEN live** (send -> sign -> status sync ->
signed date stamped -> signed PDF filed -> signer-typed PO written back, Q-206385).
Shareable version: https://claude.ai/code/artifact/026330c1-3dc7-45e4-b033-7cf24975afab
Licence model playbook: https://claude.ai/code/artifact/80330212-c87a-485c-a9f3-b918678d0185

**Critical path: the remaining UAT cells (3) and Shinae's wording sign-off (1) - no technical
blockers remain.**

## 1. Business decisions (Shinae / Finance / Kam)
- [x] **Decision 3 - legal entity table COMPLETE.** Billing Entity mapping (LBR/ALM/GHK/LLC/MBL) live in both sandboxes; governing law: ALM/LLC -> New York, LBR/GHK/MBL -> English. ALM reg number 13-3273851 added 2026-08-19.
- [x] Decisions 1/2/4/5/6 + payment-due wording - all resolved 2026-08-13 (see runbook).
- [x] **Licence models - FULLY AUTOMATIC (2026-08-20).** All four subs families derive on every line save (product rules; Law.com region rule; counts from qty/seats); 7,491 open-deal lines backfilled across both sandboxes; send-gate blocks undescribed Benefiting Group lines. Reps supply ONLY: BG description + US Law.com seats. See playbook.
- [x] **Kam sign-off (2026-08-21):** +Qty column, -Currency column (table columns are Kam's call), licence-type labels, conditional PO/VAT rows - all confirmed fine.
- [x] **General Terms alignment VERIFIED (2026-08-21):** "Authorised Users" + "Benefiting Group" are defined terms; BG members are treated as Authorised Users; clause 3.7 anchors the Order Form counts; NO Annex A exists (de-annexing correct). Notes in runbook.
- [ ] **Shinae sign-off (narrowed):** the assembled Benefiting Group sentences - especially the new Type-based draft wording ("Corporate" -> "the Customer's in-house legal function" + size, built from what reps actually capture) - plus the de-annexed Authorised Users sentence, and a nod that "Limited Access"/"Enterprise-Wide Access" work as Order Form access-type labels (not defined terms; defensible via clause 3.7). Suggested Terms addition when she next edits them: a fallback defining an unspecified Benefiting Group.
- [ ] Parked (Kam 2026-08-19/20): per-brand logos; BG phrase library + General Terms fallback sentence (need Legal); signer title write-back (ruled out).
- [x] **VAT question + guarded Account write-back - PROVEN LIVE 2026-08-23** (Kam reversed "VAT no for now"): required Yes/No "registered for VAT / GST / sales tax?", number box required on Yes; quote gets VAT_Registered__c + captured number; Account.Sales_Tax_Number__c filled ONLY when blank with a Sales_Tax_Number_Source__c provenance note for Finance review.
- [x] **"Does this order need a PO?" question (required Yes/No; PO box required only on Yes) - PROVEN LIVE 2026-08-22**: answer -> Quote.PO_Required__c, PO -> PO_Number__c. UAT cell: the No path (box hides).
- [x] **Signer-typed PO write-back - PROVEN LIVE 2026-08-22** (Kam: PO yes, VAT no for now). Direct Adobe REST form-data call from OrderFormPoWriteback; integration key (agreement_read) entered in Order_Form_Adobe_Settings__c. Phase 6: key must be hand-entered in PROD.

## 2. FULLUAT setup (Kam / admin)
- [x] **Adobe fully wired (2026-08-20):** account + Callback User linked, Automatic Status Updates enabled and proven (status pushes arrive within seconds). Note: agreements sent BEFORE enablement never update - the stale "Created" probes on Q-206385 can be cancelled in Adobe Manage.
- [x] "Send for Signature" quick action placed and used by Kam (UI send worked end to end). Confirm Signatory Contact field placement on the subs layouts.
- [ ] Assign `Order_Form_Template_Admin` to UAT testers. Test-contact rule: internal signers only; unmask the Contact email (.invalid) AND regenerate the document after.

## 3. FULLUAT testing (UAT team)
- [x] Outbound send: agreement + attached PDF (runtime variable) + Adobe document key + delivered email + signing session with correctly placed fields - PROVEN 2026-08-20 (Q-206385, Kam signed).
- [x] Real AA approval clears the DRAFT watermark - proven on Q-206385.
- [x] Product-default licence models on QLE lines - superseded: the flow now derives on every save regardless of entry route.
- [x] **Inbound round trip PROVEN (2026-08-20 evening):** status -> Signed within seconds; signed date stamped on the quote; signed PDF filed on the quote (first-party Agreement_Signed_Writeback flow + Apex - the package's data mapping is unusable with the custom Quote lookup, see runbook). Merge-mapping pre-fill fixed and completing.
- [ ] One-click UI walk incl. error screens (now also the BG send-gate screen); zero-click via opt-in checkbox.
- [x] Blank-VAT quote: superseded 2026-08-23 by the VAT question + write-back (proven).
- [x] PO question "No" path: box hides, signing completes. PASS 2026-08-22 (Kam).
- [ ] Regression: existing default template unchanged; renewal automation unaffected; renewal inheritance of licence fields (needs a contract -> renewal cycle).
- [ ] **Gate: sign-off from Kam + one rep + one Finance reviewer on the PDF output.**

## 4. Finalisation after testing (Claude Code)
- [ ] Flip Adobe tags black 8px -> white 5px in sections 01/04/08 + re-push (placement looked right in Kam's signing session - flip on his word).
- [ ] Apply Legal/UAT wording tweaks from the sign-off sitting.
- [x] Branch current: all work through 2026-08-22 committed and pushed to order-form-v1.2 (50e98ab).

## 5. Production go-live (gated)
- [ ] **Kam types: DEPLOY TO PRODUCTION CONFIRMED.**
- [ ] Deploy metadata with RunSpecifiedTests = OrderFormSignatureService_Test, OrderFormSignedWriteback_Test, OrderFormPoWriteback_Test (PROD has pre-existing red tests).
- [ ] Activate the 6 flows post-deploy (PROD deploys flows as Draft): Quote_Stamp_Order_Form_Fields, QuoteLine_Stamp_License_Model, Quote_Send_Order_Form_One_Click, Quote_Send_Order_Form_Zero_Click, Quote_Sync_Captured_VAT_to_Account, Agreement_Signed_Writeback.
- [ ] Hand-enter the Adobe integration key in PROD: Setup > Custom Settings > Order Form Adobe Settings (secret - never deployed). Verify PROD Adobe automatic status updates are enabled.
- [ ] Run in order with CONFIRM_PROD=YES: `upload-brand-assets.js` -> `push-template-content.js` -> `create-agreement-template.js` -> `seed-license-models.js` -> `sweep-license-models.js --apply` (backfills open-deal lines; expect segment-VR stragglers).
- [ ] Permission set to subs sales group; quick action onto PROD layout.
- [ ] Smoke test: one internal quote end-to-end with an internal test signer.
- [ ] Cutover decision: template ships non-default; confirm org-default flip vs subs-team selection. Announce to sales ops.
- Rollback at any point: template non-default + `Order_Form_Settings.Default.Active__c` kill switch + pull quick action from layout.
