# REV-57 — KJDEV Demo Walkthrough (2026-06-10)

**Org:** KJDEV sandbox. **State:** cutover config — flow (1) deactivated, new orchestrator + cross-linker + conversion-relink all active. Layout now shows the new fields + **Linked Form Completions** related list.

Lightning base: `https://lawbusinessresearch--kjdev.sandbox.lightning.force.com/lightning/r/`

---

## Demo A — Forward cross-link: Newsfeed registration links to an existing open inbound

*Aisha Patel had an open Lexology inbound enquiry; she then signs up for the free newsfeed. The new newsfeed record auto-links to her open inbound — same person, same brand.*

1. **Newsfeed PFC** (the new one) — open it:
   `…/Pardot_Form_Completion__c/a5EAe00000FSYT2MAP/view`
   - Record type **Newsfeed Subscribers**, **PFC Source = Newsfeed**, **Product Brand = Lexology**, **Form Name blank** (identity never parsed from the subject).
   - **Related Form Completion** field is populated → points to the inbound enquiry.
2. **Inbound PFC** — open it:
   `…/Pardot_Form_Completion__c/a5EAe00000FSYT1MAP/view`
   - Scroll to **Linked Form Completions** related list → the newsfeed record shows here (reverse direction, no second field needed).

## Demo B — Reverse cross-link: a new inbound links to an existing open newsfeed

*Ben Carter was already a free newsfeed subscriber; he then submits an inbound Lexology form. The new inbound auto-links back to his open newsfeed record — proving the link is symmetric.*

1. **Inbound PFC** (the new one):
   `…/Pardot_Form_Completion__c/a5EAe00000FSYT4MAP/view`
   - **Related Form Completion** → points to the newsfeed record.
2. **Newsfeed PFC**:
   `…/Pardot_Form_Completion__c/a5EAe00000FSYT3MAP/view`
   - **Linked Form Completions** related list shows the inbound.

## Demo C — Lead conversion relink (your bug) — *live click*

*Clara Nantes is a Lead with an open PFC. Convert her and watch the PFC move to the Contact automatically — no stage-move needed.*

1. **PFC before conversion**:
   `…/Pardot_Form_Completion__c/a5EAe00000FSYT5MAP/view` → **Lead** populated, **Contact** blank.
2. **Lead** — open and Convert:
   `…/Lead/00QAe00000QtqgXMAR/view` → click **Convert** (accept defaults).
3. Refresh the PFC → **Contact now populated, Lead cleared**, instantly. (Old behaviour: stayed on the Lead until you moved the stage.)

---

## Talking points
- One **CMDT-driven** orchestrator now handles all four sources (NF / PFC: / Lead scoring MQL / EVT) and **replaces** the old flow.
- Cross-linking is a **single shared rule**, symmetric, and **brand-precise** (a GAR form won't link to a Lexology one; an "Other"/unbranded form won't false-link).
- Closed records (Converted/Disqualified) are never linked.
- Assignment is untouched — still **Clay** (Ashton). New records land with `Clay_Routed = false` exactly like inbound.
- Bulk-safe (200 in one transaction), and every DML faults open with a `Flow_Log__c` entry.

## Verified before this demo (KJDEV)
Phase 4: 10/10 scenarios PASS (NF create, both cross-link directions, legacy-brand symmetry, closed/different-brand/Other no-link, hyphenated name, bulk-200, inbound regression vs flow 1, non-matching prefix, fault injection).

## Not yet done (post-demo)
- Phase 3 aesthetics (highlights panel, Path, compact layouts, list views, Dynamic Forms).
- Pardot `NF -` Task config (your team).
- Prod cutover plan.
