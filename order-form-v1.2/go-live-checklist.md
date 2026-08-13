# Order Form v1.2 - go-live checklist (as of 2026-08-13)

Build phases 0-5 complete; full stack deployed to FULLUAT. Shareable version:
https://claude.ai/code/artifact/026330c1-3dc7-45e4-b033-7cf24975afab

**Critical path: §2.1 (Adobe re-link) and §1.1 (entity table) - everything else can run in parallel.**

## 1. Business decisions (Shinae / Finance / Kam)
- [x] **Decision 3 - legal entity table: RESOLVED 2026-08-13.** Kam supplied the Billing Entity mapping (LBR/ALM/GHK/LLC/MBL) with legal names, reg numbers, offices; deployed to KJDEV + FULLUAT, keyed on Opportunity.Billing_Entity__c with sales-rep fallback. Governing law resolved same day: Americas entities (ALM, LLC) -> New York; LBR, GHK, MBL -> English law; final clauses deployed, draft markers removed. Only residue: ALM GLOBAL, LLC registration number (renders blank).
- [x] Decision 1 - RESOLVED 2026-08-13: optional Contact lookup on Quote, entered per quote (built as such; needs layout placement with the quick action).
- [ ] Decision 2 - missing section 5: typo or deleted (one-line renumber).
- [x] Decision 4 - CONFIRMED 2026-08-13: Net Total is the per-line annual fee.
- [x] Decision 5 - CONFIRMED 2026-08-13: signatory defaults from Main/commercial contact, rep can override.
- [x] CONFIRMED 2026-08-13 (Kam): payment-due renders the quote's live payment terms. Font: Helvetica stands in for Aptos (accepted via brand review).
- [ ] Decision 6 - General Terms URL live at centellic.com before first customer send.

## 2. FULLUAT setup (Kam / admin)
- [ ] **Re-link Adobe Sign account** (Adobe Sign Admin tab, interactive OAuth) - refresh severed it; gates all send tests.
- [ ] Quote layout updates: "Send for Signature" quick action + Legal/Notices Contact + Signatory Contact fields on the subs Quote layout(s).
- [ ] Assign `Order_Form_Template_Admin` to UAT testers.

## 3. FULLUAT testing (UAT team - remaining cells from uat/UAT-results-kjdev.md)
- [ ] Full round trip: edit+save a subs quote (first save stamps company block), approve, generate, send to test mailbox, sign; verify tag placement.
- [ ] Write-backs: PO -> quote, VAT -> quote -> account, signed date -> quote, signed PDF filed on quote; agreement links to quote.
- [ ] One-click UI walk incl. all three precondition error screens; zero-click via opt-in checkbox.
- [ ] Real AA approval clears the DRAFT watermark and fires zero-click (API-only status flips did not clear it in KJDEV).
- [ ] Regression: existing default template unchanged; renewal automation unaffected.
- [ ] **Gate: sign-off from Kam + one rep + one Finance reviewer on the PDF output.**

## 4. Finalisation after testing (Claude Code)
- [ ] Real entity values into `Legal_Entity_Document_Config__mdt` (from decision 3) + redeploy.
- [ ] Flip Adobe tags black 8px -> white 5px in sections 01/04/08 + re-push, once placement confirmed.
- [ ] Apply Legal/UAT wording or layout tweaks (incl. section renumber per decision 2).
- [ ] Commit + push branch (watermark work, brand assets, FULLUAT log currently uncommitted); merge when testing closes.

## 5. Production go-live (gated)
- [ ] **Kam types: DEPLOY TO PRODUCTION CONFIRMED.**
- [ ] Deploy metadata with RunSpecifiedTests = OrderFormSignatureService_Test (PROD has pre-existing red tests).
- [ ] Activate the 4 flows post-deploy (PROD deploys flows as Draft - org setting).
- [ ] Run in order with CONFIRM_PROD=YES: `upload-brand-assets.js` -> `push-template-content.js` -> `create-agreement-template.js` (fully org-portable; no re-keying).
- [ ] Permission set to subs sales group; quick action onto PROD layout.
- [ ] Smoke test: one internal quote end-to-end with an internal test signer.
- [ ] Cutover decision: template ships non-default; confirm org-default flip vs subs-team selection (runbook says flip - affects all business lines). Announce to sales ops.
- Rollback at any point: template non-default + `Order_Form_Settings.Default.Active__c` kill switch + pull quick action from layout.
