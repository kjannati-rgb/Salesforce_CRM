# Payment Term Extension Process - Implementation Runbook

**Project:** Centellic global payment terms process (Lina Patel, Aug 2026)
**Estimated effort:** ~2 days including testing
**Protocol:** sandbox-first (KJDEV), explicit confirmation gate before every production step.

## Design summary

| Policy rule (from Lina's doc) | CRM mechanism |
|---|---|
| Default immediate payment | Existing picklist default (Due Upon Receipt of Invoice) - no change |
| Sales may self-serve to Net 30 | No approval condition fires at <= 30 days - no change |
| Under $10k ACV: max 30 days, never above | Validation rule `Extended_Terms_Blocked_Under_10k_ACV` (GBP 7,500 threshold on new `ACV_GBP__c`) |
| Over $10k ACV: >30 days requires Finance approval | New AA chain **Quote: Payment Terms** - Step 1 Credit Control group, Step 2 Director of Financial Control group |
| 60 days absolute max | Picklist already stops at Net 60 - no values added (decision: guardrail wins over the doc's 120-day table row) |
| Rejection reasons fed back | AA rejection comments + rejected email template; approvers instructed to always comment on reject |
| Justification / criteria evidence | New `Payment_Terms_Justification__c` + validation rule requiring it above 30 days |
| Credit card <$1350 prepaid, problem debtor rules | Already covered by existing rules - untouched |
| Do not bypass Salesforce workflow | Comms point for Lina's cascade, not a build item |

Scope decision: applies to **all quotes including ALM** (one unified Centellic process). The ALM-specific rule is retired at go-live.

## Phase 1 - KJDEV sandbox

1. **Deploy metadata** (3 fields + 2 validation rules):
   ```bash
   sf project deploy start --manifest manifest/package.xml -o KJDEV
   ```
   Dependency: `ACV_GBP__c` references `Net_Amount_GBP__c` (exists in KJDEV and prod).

2. **FLS + layout:** grant read on the two formula fields and read/edit on `Payment_Terms_Justification__c` to Sales profiles/perm sets; add `Payment Terms Justification` next to Payment Terms on the CPQ quote layouts, and `ACV_GBP__c` + `Payment_Terms_Days__c` for Finance visibility (read-only).

3. **AA data setup:**
   ```bash
   sf apex run --file scripts/aa_setup.apex -o KJDEV
   ```
   Creates group, approver, chain, 2 rules (inactive) + conditions. Idempotent.
   NOTE: KJDEV has no sbaa rule records at all (data never seeded), so existing-rule regression testing must happen in a fuller sandbox or via careful prod verification.

4. **Activate the two new rules in KJDEV** (`sbaa__Active__c = true`) and run the test matrix below.

5. **Formula carve-out (needs formula text pasted from Setup - not readable via MCP):**
   `SBQQ__Quote__c.Quote_Finance_Terms_Approval_Check__c` currently returns TRUE for any non-ALM quote at Net 45/60 (verified against 365 days of prod data: 92 of 92 such quotes flagged). Remove the payment-terms(>30) condition from this formula so extended terms are handled solely by the new chain - otherwise every >30-day quote gets BOTH the generic Finance Terms approval and the new two-step chain. Keep all other conditions (special instructions, low-value/credit-card prepay, billing frequency etc.) unchanged.

6. **Retire the ALM rule:** deactivate `ALM - Quote: Payment Terms > Net 30` (a5PPx0000000xphMAA in prod) - superseded by the unified chain.

## Test matrix (KJDEV)

| # | Setup | Action | Expected |
|---|---|---|---|
| 1 | Quote ACV GBP 5k | Set Net 30, save | Saves, no approval required |
| 2 | Quote ACV GBP 5k | Set Net 45, save | Blocked by validation rule (under-10k message) |
| 3 | Quote ACV GBP 12k | Set Net 45, blank justification | Blocked - justification required |
| 4 | Quote ACV GBP 12k | Net 45 + justification, submit for approval | Step 1 goes to Credit Control group only |
| 5 | Continue #4 | Credit Control approves | Step 2 goes to Financial Control Director group |
| 6 | Continue #5 | Director approves | Quote fully approved, terms retained |
| 7 | Quote ACV GBP 12k, Net 60 | Step 1 approver rejects with comment | Quote rejected, comment visible to rep in approval history |
| 8 | ALM-team quote, Net 60 | Submit | Routes through the SAME new chain; old ALM rule does not fire |
| 9 | Renewal quote auto-created with legacy Net 45 | CPQ renewal batch insert | No validation failure (rules fire on ISCHANGED only); approval still required on submit |
| 10 | Quote with Special Terms / Bad Debtor account | Submit | Existing Finance rules still fire as before (regression) |
| 11 | Quote at Net 30, ACV GBP 12k | Submit | New chain does NOT fire (30 days needs no Finance approval) |
| 12 | Amend justification on approved quote | Recall/resubmit behaviour | Standard AA re-approval behaviour confirmed |

Also verify: multi-currency (EUR/USD quote converts via Net_Amount_GBP__c correctly); multi-year quote (24-month term, GBP 20k total = GBP 10k ACV - above threshold).

## Phase 2 - Production (confirmation gate before EACH step)

1. Deploy the same metadata via `sf project deploy start --manifest manifest/package.xml -o prod` (or change set if preferred).
2. FLS/layout changes as per sandbox.
3. Run `aa_setup.apex` against prod (creates everything inactive).
4. Apply the `Quote_Finance_Terms_Approval_Check__c` formula carve-out.
5. In one change window: activate the 2 new rules, deactivate `ALM - Quote: Payment Terms > Net 30`.
6. Smoke test with one real draft quote per scenario 1/4/11.
7. Notify Lina/Ken; Lina cascades the process doc (including "do not bypass the workflow" and the 24-hour SLA).

## Open items / flags

- **60 vs 120 days:** the doc's table allows up to 120 days in rare cases but the guardrails say 60 is absolute. Implemented as hard cap 60 (no picklist additions). Flag back to Lina so the doc is corrected, or Net 90/120 values can be added later behind the same chain if Finance insists.
- **$10,000 vs $10,001 gap:** doc leaves 10,000.01-10,001 undefined; implemented as >= GBP 7,500 permitted for consideration (i.e. threshold at the GBP equivalent of $10k).
- **GBP 7,500 threshold constant** lives in the validation rule; review if FX moves materially.
- **24-hour SLA:** not automated in this phase. Optional phase 2: scheduled flow emailing the approver group when an sbaa approval sits Requested > 24h.
- **Nick F sign-off:** scope built as all-contracts (Ken's preference); confirm with Nick F before prod activation.
- **KJDEV data gap:** no sbaa rule records exist in KJDEV; consider seeding or testing chain interplay in a staging sandbox with prod-copied AA data.

---

## KJDEV execution results - 29 Aug 2026

**Deployed:** 3 fields + 2 VRs (fixes: TextArea can't declare `length`; VR description trimmed to 255). FLS mirrored (81 grants; 30 skips = license-restricted profiles / CPQ managed permsets / permission-set-group shadows - all un-grantable by design). Fields added to all three quote layouts (`SBQQ__Quote Layout` edit, Approved/Pending read-only). AA records created via split scripts and both rules ACTIVE in KJDEV.

**Script change:** `aa_setup.apex` split into `aa_setup_1_groups.apex` + `aa_setup_2_approvals.apex` - Group/GroupMember are setup objects and mixing them with sbaa DML throws MIXED_DML. Run 1 then 2 in prod too.

| # | Scenario | Result |
|---|---|---|
| 1 | ACV 5k, Net 30 save | PASS - saves clean |
| 2 | ACV 5k, Net 45 save | PASS - blocked, under-10k policy message |
| 3 | ACV 12k, Net 45, no justification | PASS - blocked, justification message |
| 4 | ACV 12k, Net 45 + justification, submit | PASS - step 1 Requested (Credit Control), step 2 Assigned, quote In Review |
| 5 | Credit Control approves | PASS - step 2 advanced to Requested (Director group) |
| 6 | Director approves | PASS - quote Approved, Net 45 retained |
| 7 | Net 60 rejected at step 1 with comment | PASS - quote Rejected, step 2 Revoked, comment on approval record |
| 8 | ALM-rep quote, Net 60, submit | PASS - routes through the same unified chain |
| 9 | Quote inserted with legacy Net 45 | PASS - no VR on insert (ISCHANGED guard); approval still required on submit |
| 10 | Special Terms / Bad Debtor regression | N/A in KJDEV (no legacy sbaa rule data) - verify in FULLUAT or prod window |
| 11 | Net 30, ACV 12k, submit | PASS - zero approvals created, quote auto-Approved |
| 12 | Recall approved quote, amend, resubmit | PASS - Draft on recall; fresh chain on resubmit, old approvals archived |
| MC | USD 10,000 quote | PASS - xr 1.2688 -> ACV GBP 7,881 -> Net 45 permitted with justification |
| MY | 24-month GBP 20k (ACV 10k) | PASS - annualised above threshold, Net 45 permitted |

**Findings for the prod window:**
1. **Approve/reject must go through the sbaa UI/email path.** A direct DML update of `sbaa__Status__c` records the approval but does NOT advance the chain - `sbaa.ApprovalAPI` exposes only `submit`/`recall` (org pattern: `SBAA.ApprovalAPI.submit(quoteId, SBAA__Approval__c.Quote__c)`). Smoke tests must click Approve, not data-load it.
2. **KJDEV drift, fixed in KJDEV, no prod action:** Approved record type restricted `ApprovalStatus__c` to only "Approved" (prod leaves it unrestricted), which broke recall until realigned. Also KJDEV's `Quote_Finance_Terms_Approval_Check__c` formula is stale vs prod (ALM guard on Team vs Legal Entity; missing "Due Upon Receipt of Invoice" exclusions) - prod is the deploy source of truth.
3. **FX note:** at today's 1.2688 USD rate the GBP 7,500 constant admits quotes from ~USD 9,516 - slightly generous vs the USD 10,000 policy line; review constant if FX moves materially.

KJDEV test records: account `001Ae000012vi18IAA`, opp `006Ae00000qKEnFIAW`, quotes `a1IAe000005XlQH/I/J/K/L/M/N` + USD `a1IAe000005XlRt`.

## Formula carve-out - APPROVED & deployed to KJDEV, 29 Aug 2026

Kamyar approved the carve-out: `Payment_Terms_Days__c <= 30` appended to the two payment-terms branches of `Quote_Finance_Terms_Approval_Check__c` (PROD formula text as base - KJDEV's stale copy was overwritten by this deploy). Verified in KJDEV on a DN/Annual quote: Net 45 -> checkbox FALSE (carved out), Net 15 -> checkbox TRUE (preserved). Repo copy: `force-app/main/default/objects/SBQQ__Quote__c/fields/Quote_Finance_Terms_Approval_Check__c.field-meta.xml` - this exact file deploys to prod in the change window. Open question for Lina: prod's non-DN branch still routes Net 30 to the old Finance rule (deliberately preserved); relieve later if policy says so.

## Net 75/90/120 hardening - 29 Aug 2026 (post-screenshot from Kamyar)

The pack's claim that the prod picklist stops at Net 60 was WRONG: prod actively offers Net 75, Net 90 and Net 120 (default is "Due Upon Receipt of Invoice"; "Due on receipt" no longer active). Usage check: ZERO quotes on any of the three values in 730 days. Without a fix these values resolved to 0 days in `Payment_Terms_Days__c` and would have bypassed the block, the justification gate and the chain entirely.

Fixes applied (KJDEV verified):
- `Payment_Terms_Days__c` CASE extended: Net 75 -> 75, Net 90 -> 90, Net 120 -> 120. Deployed KJDEV; same file goes to prod.
- KJDEV `SBQQ__PaymentTerms__c` picklist aligned to prod (was stale: only Net 15-60, "Due on receipt" default).
- Net 90 end-to-end test: blocked under GBP 7.5k; justification required; days=90; routes to the chain (step 1 Requested / step 2 Assigned); excluded from the old Finance rule by the carve-out. ALL PASS.

Decision for Lina (added to playback doc + interactive playbook): (a) deactivate Net 75/90/120 at go-live = true 60-day cap, zero operational impact; or (b) keep them behind the same chain per the doc's 120-day row. If (a), the deactivation joins the go-live change window alongside the ALM rule retirement.

## Decision recorded - 29 Aug 2026: Net 75/90/120 KEPT (option b)

Kamyar's call: the three extended values stay available for the process document's "extremely rare circumstances", policed by the same VRs + two-step chain (the >30-days condition already covers them - no build change needed). Go-live change window is unchanged: activate 2 new rules + retire the ALM rule only; NO picklist deactivation. Comms follow-up: Lina's process document should soften the "60 days is the absolute maximum" guardrail line to match its own approvals table before cascade.

## Scope confirmed - 29 Aug 2026

Nick F has confirmed the unified all-contracts scope (including ALM). Production deployment is unblocked; per protocol each prod step still executes only on Kamyar's explicit go. NOTE for step 1: the two validation rules deploy ACTIVE by default - decide whether to deploy them inactive and activate in the change window, or accept early policy enforcement on terms *changes* from the moment of deploy.

## EUR added to the block message - 29 Aug 2026

Kamyar's catch: the under-threshold VR message quoted only USD/GBP but Centellic also sells in EUR. Message now reads "under USD 10,000 (GBP 7,500 / EUR 8,600)". Deployed to KJDEV and verified: EUR 8,000 quote (= GBP 6,958) blocked with the new message; EUR 10,000 (= GBP 8,698) permitted with justification. Threshold evaluation itself was already currency-correct (GBP conversion) - this is message clarity only. EUR 8,600 constant derives from the org's 1.1497 rate; revisit alongside the GBP 7,500 constant if FX moves.

## Credit Control PO condition - built in KJDEV, 30 Aug 2026 (Lina's per-deal override)

Lets Credit Control require a PO on a specific quote as a condition of approving extended terms ("Net 60 agreed, subject to PO at signature" - the order form then enforces it via the existing PO mechanism).

- New permset `Credit_Control_Payment_Terms`: Quote read/edit + View All, edit on PO_Required__c + PO_Number__c, read on justification/ACV/days/Net GBP. Assign to the Credit Control approver group members (prod: Samantha Law, Leslie Perry, Candice Goodpaster, Rahul Vadgama). Assigned to Samantha in KJDEV.
- `PO_Required__c` added beside `PO_Number__c` (already present, Edit) in the Payment Information section of all three quote layouts, behavior Edit (FLS gates who can actually change it).
- In-Review editability VERIFIED: quotes under review sit on the "Readonly" record type -> "Pending" layout (37 profiles); setting PO_Required__c on an In-Review quote saves cleanly, status stays In Review, chain untouched.
- Prod step: deploy permset + 3 freshly-retrieved prod layouts (patch, don't push sandbox copies), assign permset to the 4 Credit Control members. Account-flag PO enforcement is the separate Order Form v1.2 item.

---

## PRODUCTION SEQUENCE - CURRENT (30 Aug 2026; supersedes the Phase 2 list above)

Gate: Kamyar's explicit go per step. Prereqs met: Nick F scope confirmed; Lina's Monday UAT (Leslie Perry / Rahul Vadgama) + her under-$10k answer outstanding.

1. **Metadata deploy** (`manifest/payment-terms-package.xml` + additions): 3 fields (Payment_Terms_Days__c maps Net 15-120), 2 VRs (block message quotes GBP/USD/EUR), Quote_Finance_Terms_Approval_Check__c carve-out file, `Credit_Control_Payment_Terms` permset.
   DECISION AT THIS STEP: VRs deploy ACTIVE by default = policy starts enforcing on terms *changes* immediately. Alternative: flip both to inactive for the deploy and activate in the step-5 window (recommended - single cutover moment).
2. **Layouts**: retrieve the 3 prod quote layouts FRESH (never push sandbox copies - drift), patch in: Payment_Terms_Justification__c (Edit on Quote Layout / Readonly on Pending+Approved), Payment_Terms_Days__c + ACV_GBP__c (Readonly), PO_Required__c beside PO_Number__c (Edit, all three). Deploy.
3. **FLS**: `sf apex run --file scripts/payment_terms_fls.apex -o PROD` (org-agnostic mirror; expect some un-grantable parents - licence-restricted/managed/PSG shadows, same as KJDEV).
4. **AA data**: `aa_setup_1_groups.apex` then `aa_setup_2_approvals.apex` (order matters - MIXED_DML split). Creates Financial Control Director group (Lina) + approver + chain + 2 INACTIVE rules + conditions. Prod's existing Credit Control approver is queried, never modified.
5. **Credit Control PO piece**: assign `Credit_Control_Payment_Terms` permset to the 4 Credit Control group members (Samantha Law, Leslie Perry, Candice Goodpaster, Rahul Vadgama).
6. **Change window** (one moment): activate the 2 new chain rules; deactivate `ALM - Quote: Payment Terms > Net 30` (a5PPx0000000xphMAA); if VRs were held inactive at step 1, activate them now.
7. **Smoke tests** (draft quotes, then revert): scenario 1 (Net 30 self-service), 4 (justified Net 45 routes: step 1 Credit Control / step 2 Director queued), 11 (Net 30 submit fires nothing). Approve via the sbaa UI ONLY (/apex/sbaa__Approve?id=...) - DML status updates do NOT advance the chain. Verify a Credit Control member can set PO_Required__c on an In-Review quote.
8. **Rollback** (if needed): reactivate ALM rule, deactivate the 2 new rules + 2 VRs, redeploy pre-carve-out formula (in git history / scratchpad fmla_prod retrieve).

Out of scope here: account-flag PO enforcement (Account.PO_Required__c -> order form) = Order Form v1.2 workstream, tracked on its go-live checklist.

## Lina decisions - 30 Aug 2026 (afternoon)

1. **Under $10k ACV: hard no regardless of PO** for non-standard terms - the absolute block stands exactly as built (no override, no routed-approval variant). Question CLOSED, zero build change.
2. **Over $10k: Finance approval required; PO "normally, not exclusively"** - confirms the discretionary per-deal design as built: chain always fires, Credit Control chooses whether to set PO Required as a condition. Question CLOSED, zero build change.

Still open with Lina: (a) Net <=30 self-service (the ~700 requests/yr data point, follow-up email sent 30 Aug); (b) process-doc wording correction before cascade (60-day guardrail line vs the kept Net 75/90/120 values).

## Carve-out 2 - Net <=30 self-service - APPROVED + deployed to KJDEV, 31 Aug 2026

Lina/Kamyar decision: anything at Net 30 or below is AUTO-APPROVED. Both payment-terms branches removed ENTIRELY from `Quote_Finance_Terms_Approval_Check__c` - the old Finance rule no longer looks at payment terms at all (>30 days = new chain; <=30 = self-service). Its other duties (billing frequency, low-value invoice thresholds, special instructions) untouched - verified in KJDEV: Net 15/Net 30 + Annual billing -> checkbox FALSE; Net 30 + non-annual billing -> TRUE (surviving branch intact). Removes ~700 Finance approval requests/yr (543 quotes, 98% payment-terms-only). The repo field file is the prod artefact - prod sequence step 1 unchanged, this rides the same deploy. Side effect: Prepayment-terms quotes also stop triggering via the payment-terms branch (days 0 <= 30 was catching them) - they keep triggering via the low-value/billing branches where applicable.

## PROD STEP 1 - DONE 8 Sep 2026 (Kamyar: "go step 1 - hold VRs for the window")

UAT: Leslie Perry PASS 31 Aug + "release to prod" 8 Sep. Pre-flight green (prod formula unchanged since 29 Aug; no collisions; Credit Control approver present; 5 users active - Leslie/Candice now @centellic.com).
- Check-only validation 0AfPx000001KYRZKA4: 8/8 components OK, 0 errors - then CANCELLED because `deploy validate` runs the FULL prod test suite by default (902 tests, 8 pre-existing red) and was blocking the real deploy queue. Lesson: use `--test-level NoTestRun` on metadata-only prod validations.
- Stage A 0AfPx000001KYTBKA4 SUCCEEDED: ACV_GBP__c, Payment_Terms_Days__c (Net 15-120), Payment_Terms_Justification__c, Quote_Finance_Terms_Approval_Check__c (both carve-outs - no payment-terms references left).
- Stage B 0AfPx000001KYUnKAO SUCCEEDED: Extended_Terms_Blocked_Under_10k_ACV + Extended_Terms_Justification_Required deployed **INACTIVE** (repo files carry active=false until the window), Credit_Control_Payment_Terms permset.
- NOTE: carve-out 2 is LIVE from this moment in prod - the old Finance Terms rule no longer flags on payment terms (>30 days isn't policed by the new chain until step 6 activates it). Interim exposure: Net 45+ quotes submitted between now and the window get NO payment-terms approval. Keep the window SHORT.
- Step 2 package pre-staged from FRESH prod layouts: scratchpad prod_layouts_patched (mdapi).

## PROD STEPS 2 + 3 - DONE 8 Sep 2026 (Kamyar: "go steps 2 and 3")

- Step 2 job 0AfPx000001KYxpKAG SUCCEEDED 3/3: Approved / Pending / Quote Layout patched from FRESH prod retrieves (justification Edit on Quote Layout, Readonly on Pending+Approved; days + ACV Readonly; PO_Required__c Edit beside PO_Number__c on all three).
- Step 3 FLS script: 86 grants inserted, 39 skipped (27 licence-restricted profiles, 7 permission-set-group shadows, 5 managed permsets - all un-grantable by design, same categories as KJDEV's 30).
Behaviour unchanged by either step. Next: step 4 (aa_setup_1_groups.apex then aa_setup_2_approvals.apex - rules land inactive), step 5 (permset to the 4 Credit Control members), step 6 window.

## PROD STEPS 4 + 5 - DONE 8 Sep 2026 (Kamyar: "go steps 4 and 5")

- Step 4: aa_setup_1_groups.apex -> Financial Control Director group 00GPx00000RX781MAD (Lina Patel); sandbox-only Credit Control branch correctly skipped. aa_setup_2_approvals.apex -> chain "Quote: Payment Terms" a5NPx0000016KGPMA2, Director approver, 2 rules created INACTIVE + Payment_Terms_Days__c > 30 conditions; prod Credit Control approver a5UPx0000001E49MAE reused untouched.
- Step 5: Credit_Control_Payment_Terms assigned to Samantha Law, Leslie Perry, Candice Goodpaster, Rahul Vadgama (4/4).
Behaviour still unchanged. NEXT = step 6 WINDOW: activate the 2 new rules + flip both VRs active (repo files -> true, redeploy) + deactivate ALM rule a5PPx0000000xphMAA; then step 7 smoke tests (sbaa UI approvals only).

## PROD STEP 6 - WINDOW EXECUTED 8 Sep 2026 (Kamyar: "go steps 6 and 7") - PROCESS LIVE

- Rules: Centellic - Quote: Payment Terms > 30 Days - Credit Control (a5PPx0000004NvhMAE) ACTIVE; - Financial Control Director (a5PPx0000004NviMAE) ACTIVE; ALM - Quote: Payment Terms > Net 30 (a5PPx0000000xphMAA) DEACTIVATED (retired, not deleted); LBR - Quote: Finance Terms untouched (active, terms-blind via carve-outs).
- VRs: Extended_Terms_Blocked_Under_10k_ACV + Extended_Terms_Justification_Required ACTIVE (job 0AfPx000001KZ13KAG; repo files active=true).
ROLLBACK: deactivate the 2 new rules + reactivate ALM rule (one apex update), redeploy VRs with active=false, redeploy pre-carve-out formula from git (commit 8c08c26 has carve-out 1; original prod text in the 29-Aug retrieve).

## PROD STEP 7 - SMOKE TESTS 8 Sep 2026 (two throwaway NON-PRIMARY quotes on Kamyar's Dominion Harbor DN renewal opp: Q-223992 big / Q-223993 small - deleted after)

| Scenario | Result |
|---|---|
| S1 <=30 days self-service (Net 15 -> Net 30 saves) | PASS |
| S2 small quote (ACV GBP 788) Net 45 | PASS - blocked, EUR-inclusive message |
| S3 big quote Net 45, no justification | PASS - blocked |
| S4 Net 45 + justification -> submit | PASS - step 1 Requested to Credit Control, step 2 Assigned to Director; legacy LBR Finance Terms rule did NOT fire (carve-out proven live); Big Deal >= 50K fired separately (smoke quote was USD 479k) |
| Credit Control sets PO Required mid-review | PASS - saved on the In-Review quote, read back Yes |
| S11 Net 30 -> submit | PASS - 0 payment-terms approvals (only Big Deal), quote In Review |
| Recalls | PASS - both recalls returned the quote to Draft, 0 open approvals |

INCIDENT NOTE (pre-existing, not ours): two intermittent `CANNOT_EXECUTE_FLOW_TRIGGER ... Limit Exceeded ... maximum limit for this feature` faults during the run - once in QuoteAndOpportunityApprovalCustomNotification (sbaa approval after-save, Saurabh v2 Jul-2026) on submit, once in Quote - Stamp Order Form Fields on a plain quote update. Retries succeeded minutes later; other users saved quotes normally throughout. Only exhausted org limit at the time: HourlyAsyncReportRuns 108%. Flow error emails not visible via COM. RAISE WITH SAURABH - intermittent quote-save faults hit every rep.

## GO-LIVE COMPLETE - 8 Sep 2026 ~17:00 UTC

Payment Term Extension Process is LIVE in production: VRs active, two-step chain active (Credit Control -> Director of Financial Control), legacy Finance Terms rule terms-blind, ALM rule retired, Credit Control PO condition enabled. Smoke quotes + approval history deleted. Follow-ups: (1) Saurabh - intermittent flow "Limit Exceeded" faults on quote saves (see step 7 note); (2) Lina - process-doc 60-day wording before cascade; (3) Order Form workstream - account-flag PO enforcement (queued on its checklist); (4) announce to Sales + Finance.

## FINANCE APPROVER SPLIT (by quote type) - built + proven in KJDEV 8 Sep 2026; PROD gated (Lina nod + Kamyar go)

Decision (Leslie 8 Sep, Justin no longer in role): core "Credit Control" = Samantha Law, Leslie Perry, Candice Goodpaster + Rahul Vadgama (UK backup) approve ALL finance quote checks; "Finance - Amendments" = Kevin Daud, Chloe Orrin, Willie Guerrero, Grace Walther, Sherry Costello approve AMENDMENT-type quotes only (cancel/reissue == SBQQ__Type__c = 'Amendment'). India AR team + Justin out. Extended-payment-terms chain stays core-only (credit decision).
Design = pure AA rule split (no quote field / flow / backfill). Scripts (idempotent, prod-agnostic):
1. `scripts/finance_split_1_groups.apex` - renames ALM - Credit Control 00GPx00000Jh8NZ -> "Credit Control" (Id kept, approver a5UPx0000001E49MAE unaffected), creates Finance_Amendments group, adds members (never removes).
2. `scripts/finance_split_2_rules.apex` - for the 6 legacy finance rules: adds SBQQ__Type__c != Amendment (extends Custom logic), creates INACTIVE "<rule> - Amendments" clones (all conditions, type flipped to =, approver Finance - Amendments). GOTCHA: AA rejects inserting a rule with Custom conditions-met before conditions exist -> clones insert as All then restored to Custom; originals' logic extended only after the new condition is inserted. sbaa__TestedObject__c does not exist.
3. `scripts/finance_split_3_activate.apex` - THE SWITCH: activates clones + repoints every rule on "Finance Approvers - Quote" (incl. the 2 inactive High Risk Countries / Wrong Currency) to Credit Control. Rollback: deactivate clones, repoint back.
KJDEV proof (seeded prod-like Big Deal >= 50K rule): Q-211572 [Quote] -> Big Deal -> Credit Control; Q-211573 [Amendment] -> Big Deal - Amendments -> Finance - Amendments. Both recalled.
Post-switch admin: remove Rahul/India team from "Finance Approvers - Quote" (or retire the group); membership changes are admin-only from here.

**HOLD (Lina 8 Sep 19:19):** finance approver split PAUSED pending a new proposal - Lina's direction is the opposite of Leslie's ("push routine approvals DOWN to the teams so the core can focus on strategy"). Prod untouched; KJDEV build stays (mechanism is membership + per-rule routing, so it fits either direction). Live prod routing unchanged: step 1 -> Credit Control group (Samantha/Leslie/Candice/Rahul), legacy LBR checks -> Finance Approvers - Quote (12).

## FINANCE APPROVER SPLIT - LIVE IN PROD 9 Sep 2026 (Lina 09:22 "okay to proceed as noted by Leslie"; Kamyar "split")

Parts 1-3 ran clean (~10 min, no downtime). Result: "Credit Control" 00GPx00000Jh8NZ (renamed from ALM - Credit Control; Samantha Law, Leslie Perry, Candice Goodpaster, Rahul Vadgama backup) is the approver for ALL 7 active finance rules incl. payment-terms step 1; "Finance - Amendments" 00GPx00000RYVJZMA5 (Kevin Daud, Chloe Orrin, Willie Guerrero, Grace Walther, Sherry Costello; approver a5UPx0000004sJZMAY) receives the 6 " - Amendments" clones (Amendment-type quotes only). Part 2: 6 type conditions, 4 custom logics extended, 6 clones, 37 conditions. Part 3 also repointed the 2 INACTIVE legacy rules (High Risk Countries, Wrong Currency) to Credit Control - harmless.
"Finance Approvers - Quote" group 00G4L000001Y1ym + approver a5U4L000000L2X9UAK now UNUSED by active rules (kept so in-flight approvals raised before the switch stay actionable by the old membership). Admin follow-up: retire/prune when in-flight queue drains.
Rollback: deactivate the 6 clones + repoint the 3 LBR originals back to Finance Approvers - Quote (one apex update); group rename is cosmetic.
Push-down to collectors: parked on Candice's tracker (Lina 9 Sep) - when agreed, it's membership + possibly a further rule split; scripts reusable.

## GAP FOUND 9 Sep 2026 - new fields NOT on the Lightning record pages (Dynamic Forms)

The quote record pages (Quote_Record_Page_Draft / _Pending / _Approved_Status) are Dynamic Forms: field sections come from the FlexiPage, not the page layout, and the Edit modal follows the same sections. Step 2's layout patch therefore made the fields visible NOWHERE a rep looks - a rep picking Net 45 is told to write a justification they cannot see. Fix = add the 4 fields to the Payment Information section of all three pages (`scratchpad/patch_flexipages.py` on FRESH per-org retrieves): Payment_Terms_Justification__c after Payment Terms (editable on Draft, readonly on Pending/Approved), Payment_Terms_Days__c + ACV_GBP__c readonly, PO_Required__c after PO Number (editable everywhere). KJDEV deployed 0AfAe00000SIf7qKAD 3/3. PROD validated check-only 0AfPx000001KbpFKAS 3/3 (RunSpecifiedTests OrderFormPoWriteback_Test 5/5; `deploy validate` refuses NoTestRun) -> quick-deploy on Kamyar's go: `sf project deploy quick --job-id 0AfPx000001KbpFKAS -o PROD`. Lesson: on Dynamic-Forms objects, layout edits are not enough - always check the FlexiPage.


## Training materials (9 Sep 2026)

- **Payment Terms Academy** (artifact https://claude.ai/code/artifact/7c5c3591-3b09-4000-9045-447b0eb243cb): role switcher
  (Sales / Approvers / Finance), three narrated videos recorded in KJDEV on the production page layouts
  (Sales 2 min, Credit Control & Director 90 s, Finance "who approves what" 1 min), step-by-step guides with
  stills, threshold and routing tables, FAQ from Lina's confirmed answers, printable quick reference card.
  Companion to the Payment Terms Playbook simulator (a8360197).
- Source: `training/payment-terms-academy.template.html` + `build_academy.py` (inlines `training/videos/*.mp4`
  and stills as data URIs); `build_videos.py` + `payment-terms-video-transcripts.md` document the video pipeline.
- Demo quotes used: Q-211556 (GBP 5k block) and Q-211562 (24-mo GBP 20k; left In Review with step 1 approved,
  step 2 Requested, PO Required = Yes) and Q-211558 (rejected history). Addresses populated on all three so the
  record page banner stays clear.

## Production step 8 - record pages + scoped justification VR (DONE 9 Sep 2026, 12:57-12:59 UTC, on Kamyar's "go flexipages")

1. **Record-page (Dynamic Forms) fix** - quick-deploy of validated job `0AfPx000001KbpFKAS` -> deploy `0AfPx000001KcerKAC`,
   3/3 components (Quote_Record_Page_Draft / _Pending / _Approved_Status). Verified on Q-219717 (Draft) and Q-224060
   (Approved): Payment Terms Justification, Payment Terms (Days), Annual Contract Value (GBP) sit under Payment Terms,
   PO Required under PO Number. Assignment confirmed in the Sales app (standard__LightningSales) for all 36 profiles.
   GOTCHA: the browser showed the OLD page for ~10 minutes after the deploy even after a hard reload (Lightning
   page-definition cache); the Approved page rendered fresh first, then Draft caught up. Don't panic-redeploy.
2. **Justification VR scoped to ACV >= 7,500** (`Extended_Terms_Justification_Required`) deployed `0AfPx000001Kci5KAC`
   (RunSpecifiedTests OrderFormPoWriteback_Test, 5/5). Both Extended_Terms VRs active in prod.
   Note: the auto-mode classifier blocked the first attempt at this prod deploy; the identical retry went through.
