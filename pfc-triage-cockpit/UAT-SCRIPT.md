# PFC Triage Cockpit — UAT Script (Phase F1)

**Participants:** 2–3 reps (suggest one who works lead-linked inbound + one KA/CSM-adjacent who sees contact-linked forms) + Greg / Cayla as business owners.
**Environment:** FULLUAT sandbox (`lawbusinessresearch--fulluat`) — deployed + seeded 2026-07-16. Permission sets `PFC_Triage_Cockpit_Fields` + `PFC_REV57_Field_Access` already assigned to Cayla; ask CRM Support (Kamyar) for other testers.
**Pre-flight (admin):** DONE for Cayla (no `Application_Settings__c` bypass rows; ~10 records seeded via `scripts/fulluat_seed.apex` — incl. queue-owned Task-chain records, "UAT UTM Scored" fit-score 83, contact-linked at Rouse AB [113 real subs], "UAT Disqualified", "UAT Converted", one Routing-Overdue). For additional testers repeat the bypass check.
**Word version for testers:** `UAT-SCRIPT.docx` (same content, result checkboxes + sign-off table).

Record observations per step: ✅ works / 🟡 friction (describe) / ❌ broken.

## Scenario 1 — Queue triage (rep, ~10 min)
1. Open list view **Team Triage (Unrouted Queue)** on Pardot Form Completions. Confirm you see queue-owned records with Fit Score / Routing Overdue / Source columns. Optional: switch display to Kanban grouped by Sales Stage (gear → Kanban; user-level setting).
2. Open a queue-owned record. Confirm the page shows: Key Details, Path with stage guidance, the **Lead Quality** card (score gauge or "Score pending"), Triage/Attribution/Outcome tabs.
3. Take ownership (Change Owner → you). Confirm the record leaves Team Triage and appears in **My Triage**.
4. If the record was flagged Routing Overdue: confirm the flag cleared itself when you took ownership.

## Scenario 2 — Working a lead-linked form (rep, ~15 min)
5. On a lead-linked record: check the Lead Quality card — is the duplicate warning meaningful? Click a duplicate link.
6. Move Path to **Working** (Mark as Current Stage). Fill the stage key fields (Next Step, Next Contact Date). Confirm a reminder Task is created (Activity panel).
7. Log a call from the Activity composer.
8. Use **Convert Lead** on a record you'd genuinely convert; confirm the flow behaves as in production today.

## Scenario 3 — Disqualify (rep, ~5 min)
9. On another record, click **Disqualify**. Confirm: reason required, comment optional, record lands in Disqualified with Date Completed stamped, and the Disqualify button disappears.
10. Check your comment landed in Comments (prepended if there was existing text).

## Scenario 4 — Contact-linked / existing account (KA-adjacent rep, ~10 min)
11. Open a contact-linked record (GATEC-2 style). Confirm the header shows Account + Account Owner (not Company/Sales Rep), and the card re-skins as **Account Context** with subscriptions count, holdings summary, and — where the requested brand's family is already held — the red entitlement check.
12. Click **Route to Account Team** (replaced Route to Account Owner per 21-Jul decision — account owners aren't the routing target; the firm's Account Team is): the confirmation screen names the firm's team member (preferred role per PFC Settings, default "LexPro BDM"; falls back to the firm owner with an explicit warning only when no team exists). Finish, then check the Chatter @mention on the record and the review Task assigned to that team member. On the Rouse AB test record this routes to Cayla (seeded as LexPro BDM).
13. Business check (Greg/Cayla): is the entitlement copy right? Are the brand→family mappings in `Brand_Family_Map__mdt` correct? (Current best-guess: Lexology→Subs - Lexology Pro; GAR/GCR/GIR/GRR/GDR/GBRR/IAM/WTR/Latin Lawyer→Subs - Specialist Platforms.)

## Scenario 5 — Attribution & outcome (any, ~5 min)
14. Attribution tab: UTM section appears only on the UTM-populated test record; newsfeed date only on the newsfeed record.
15. Outcome tab on a converted record: opportunity fields visible; on an open record: hidden.

## Open decisions to confirm during UAT
- Should **Convert Lead** stay visible on Disqualified records? (Currently yes, v2 parity.)
- Path guidance wording per stage (drafted copy).
- Gauge colour bands (provisional: green ≥70 / amber 40–69 / red <40) — Clay scoring owner.
- Routing SLA threshold: 4 working hours right? Alert to which Chatter group?
- Do reps miss the Lead/Contact "Related Record" sidebar panel (dropped: platform limitation)? The quality card + Key Details links are the replacement.

**Exit criteria:** all scenarios ✅/🟡 (no ❌), friction notes triaged, decisions above answered → Phase F prod deployment scheduled.
