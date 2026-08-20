# Order Form v1.2 - go-live checklist (as of 2026-08-20)

Build phases 0-5 complete; full stack deployed to FULLUAT; outbound Adobe send PROVEN live.
Shareable version: https://claude.ai/code/artifact/026330c1-3dc7-45e4-b033-7cf24975afab
Licence model playbook: https://claude.ai/code/artifact/80330212-c87a-485c-a9f3-b918678d0185

**Critical path: enable Adobe automatic status updates (2.1) - it gates the inbound half of the
round trip (status sync, write-backs, signed-PDF filing). Everything else can run in parallel.**

## 1. Business decisions (Shinae / Finance / Kam)
- [x] **Decision 3 - legal entity table COMPLETE.** Billing Entity mapping (LBR/ALM/GHK/LLC/MBL) live in both sandboxes; governing law: ALM/LLC -> New York, LBR/GHK/MBL -> English. ALM reg number 13-3273851 added 2026-08-19.
- [x] Decisions 1/2/4/5/6 + payment-due wording - all resolved 2026-08-13 (see runbook).
- [x] **Licence models - FULLY AUTOMATIC (2026-08-20).** All four subs families derive on every line save (product rules; Law.com region rule; counts from qty/seats); 7,491 open-deal lines backfilled across both sandboxes; send-gate blocks undescribed Benefiting Group lines. Reps supply ONLY: BG description + US Law.com seats. See playbook.
- [ ] **Shinae sign-off list:** +Qty column, -Currency column, licence-type labels, assembled Benefiting Group wording, de-annexed Authorised Users sentence, conditional PO/VAT rows. One sitting, on a rendered PDF.
- [ ] Parked (Kam 2026-08-19/20): per-brand logos; BG phrase library + General Terms fallback sentence (need Legal); signer title write-back (ruled out).

## 2. FULLUAT setup (Kam / admin)
- [x] **Adobe account + Callback User linked (2026-08-20).** The copied prod link worked; probe agreements reached Adobe with correct PDF + recipient.
- [ ] **Confirm "Enable Automatic Status Updates" ran** (Adobe Admin tab > Resources) - agreements stay "Created" locally until Adobe can push events back.
- [ ] Quote layout updates: "Send for Signature" quick action + Signatory Contact field on the subs Quote layout(s).
- [ ] Assign `Order_Form_Template_Admin` to UAT testers. Test-contact rule: internal signers only; unmask the Contact email (.invalid) AND regenerate the document after.

## 3. FULLUAT testing (UAT team)
- [x] Outbound send: agreement + attached PDF (runtime variable) + Adobe document key + delivered email + signing session with correctly placed fields - PROVEN 2026-08-20 (Q-206385, Kam signed).
- [x] Real AA approval clears the DRAFT watermark - proven on Q-206385.
- [x] Product-default licence models on QLE lines - superseded: the flow now derives on every save regardless of entry route.
- [ ] **Inbound: status sync + write-backs (PO/VAT/signed date) + signed-PDF filing** - parked 2026-08-20; resumes at 2.1 above, then re-sign a probe.
- [ ] One-click UI walk incl. error screens (now also the BG send-gate screen); zero-click via opt-in checkbox.
- [ ] Regression: existing default template unchanged; renewal automation unaffected; renewal inheritance of licence fields (needs a contract -> renewal cycle).
- [ ] **Gate: sign-off from Kam + one rep + one Finance reviewer on the PDF output.**

## 4. Finalisation after testing (Claude Code)
- [ ] Flip Adobe tags black 8px -> white 5px in sections 01/04/08 + re-push (placement looked right in Kam's signing session - flip on his word).
- [ ] Apply Legal/UAT wording tweaks from the sign-off sitting.
- [x] Branch current: all work through 2026-08-20 committed and pushed to order-form-v1.2.

## 5. Production go-live (gated)
- [ ] **Kam types: DEPLOY TO PRODUCTION CONFIRMED.**
- [ ] Deploy metadata with RunSpecifiedTests = OrderFormSignatureService_Test (PROD has pre-existing red tests).
- [ ] Activate the 4 flows post-deploy (PROD deploys flows as Draft - org setting).
- [ ] Run in order with CONFIRM_PROD=YES: `upload-brand-assets.js` -> `push-template-content.js` -> `create-agreement-template.js` -> `seed-license-models.js` -> `sweep-license-models.js --apply` (backfills open-deal lines; expect segment-VR stragglers).
- [ ] Permission set to subs sales group; quick action onto PROD layout.
- [ ] Smoke test: one internal quote end-to-end with an internal test signer.
- [ ] Cutover decision: template ships non-default; confirm org-default flip vs subs-team selection. Announce to sales ops.
- Rollback at any point: template non-default + `Order_Form_Settings.Default.Active__c` kill switch + pull quick action from layout.
