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
