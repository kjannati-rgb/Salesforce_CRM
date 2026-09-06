# Salesforce Support Case — CPQ renewal fails with DUPLICATE_VALUE on OpportunityContactRole

**Subject:** CPQ contract renewal fails with `DUPLICATE_VALUE: Contact has already been added in
that Contact Role` — no renewal Opportunity created, no debug log produced

**Product:** Salesforce CPQ (SBQQ)
**Severity requested:** High — blocks GBP 16,038 + EUR 78,750 of renewal pipeline
**Org ID:** `00D6g0000081IOgEAM` (Production, Law Business Research Ltd, Unlimited Edition, instance GBR46)
**CPQ package version:** ⚠️ *[FILL FROM Setup → Installed Packages → Salesforce CPQ]*
**Contact:** Kam Jannati, Head of Data and CRM

---

## 1. Summary

Activated contracts with a future end date and `SBQQ__RenewalForecast__c = true` fail to produce a
renewal Opportunity. Clicking **Renew** on the contract returns an error on CPQ's own
`SBQQ.ContractSave` Visualforce page. `Contract.SBQQ__RenewalOpportunity__c` remains null and no
Opportunity is created — the transaction rolls back completely.

Error text, identical across all affected contracts:

```
Error creating Opportunity: We can't save this record because the
"Opportunity_AfterUpdate_MasterFlow" process failed. Give your Salesforce admin these details.
This error occurred when the flow tried to create records:
DUPLICATE_VALUE: Contact has already been added in that Contact Role.
You can look up ExceptionCode values in the SOAP API Developer Guide.
```

## 2. Error IDs (three distinct transactions)

| Error ID | Contract | When |
|---|---|---|
| `452526092-138563 (550428964)` | 00047980, 00047867, 00047898, 00047833 | 13 Aug 2026, single bulk transaction |
| `1170089888-120116 (550428964)` | 00047980 | 15 Aug 2026, single-record retry |
| `1416266268-138797 (550428964)` | 00047980 | 15 Aug 2026, retry with contact-role cloning disabled |

## 3. Affected records

| Contract | Id | Account | Source Opportunity | Value |
|---|---|---|---|---|
| 00047833 | `800Px00000ftJ44IAE` | SAP SE | `006Tm00000GDMntIAH` | EUR 50,000 |
| 00047898 | `800Px00000g48oPIAQ` | EZ Service S.r.l. | `006Tm00000HENarIAH` | EUR 28,750 |
| 00047980 | `800Px00000gBpILIA0` | 5 Stone Buildings Caribbean | `006Px00000TP0PBIA1` | GBP 10,638 |
| 00047867 | `800Px00000fyjE7IAI` | Vivien Chan & Co | `006Px00000T08rJIAR` | GBP 5,400 |

A fifth contract (00044367, Spencer Fane LLP) failed with a different error
(`Error while saving Opportunity Line Items: socket hang up`) and **succeeded on retry** on
15 Aug — renewal Opportunity `006Px00000UBDOsIAP`. It is excluded from this case.

## 4. Steps to reproduce

1. Open Contract `800Px00000gBpILIA0` (00047980) in Lightning.
2. State: `Status = Activated`, `EndDate = 2027-05-16` (future), `SBQQ__RenewalForecast__c = true`,
   `SBQQ__RenewalQuoted__c = true`, `SBQQ__RenewalOpportunity__c = null`,
   `SBQQ__RenewalTerm__c = 12`, one active subscription.
3. Click **Renew**.
4. The `ContractSave` panel returns the error above. No Opportunity is created.

Reproduces 100% — three consecutive attempts, three distinct Error IDs.

## 5. What we have ruled out, with evidence

**a) CPQ's contact-role cloning is NOT the cause.**
We set `SBQQ__DefaultRenewalContactRoles__c = false` on 00047980 and retried. The failure was
**identical** (Error ID `1416266268-138797`). With cloning disabled, CPQ should not be copying
contact roles at all, yet the duplicate still occurs. *This is the single most important
observation in this case.*

**b) No duplicate contact roles exist in the source data.**
- 00047833: source Opportunity has 36 OpportunityContactRoles, **zero duplicate ContactIds**
  (`GROUP BY ContactId HAVING COUNT(Id) > 1` returns 0 rows). One primary: Janaka Bohr,
  Decision Maker.
- 00047980: source Opportunity has **exactly one** contact role — Matthew Paton, Decision Maker,
  `IsPrimary = true`.

**c) Our own automation cannot be the second writer.**
The only element in our flows that creates an `OpportunityContactRole` on this path is
`Opportunity_Renewal_New_Records → Create_Opportunity_Contact_Role`. It is gated on a decision
requiring **both** `Primary_Contact__c` and `Pardot_Form_Completion__c` to be non-null.
`Pardot_Form_Completion__c` is **null on all four** source Opportunities, so that element takes its
"Do Not Create" branch and never executes.

**d) Renewal flags do not discriminate.**
`SBQQ__RenewalForecast__c = true` and `SBQQ__RenewalQuoted__c = true` on both the failing contracts
and on 15 recent contracts that renewed successfully.

**e) Not a data-volume or governor issue.** No org limit above 50% consumed.

## 6. The failing transaction produces no debug log

This is our main blocker and a specific question for Support.

We set trace flags on **both** relevant users:
- `kamyar.jannati@lbresearch.com` — the user clicking Renew
- `saurabh.patil@lbresearch.com` — the user the renewal Opportunity insert runs as
  (confirmed: successfully created renewal `006Px00000UBDOsIAP` has `CreatedBy = Saurabh Patil`
  even though it was initiated by a different user through the UI)

Debug level: `WORKFLOW = FINER`, `APEX_CODE = ERROR`, `VALIDATION = INFO`, all other categories
`NONE` (deliberately starved so the log would not be truncated — an earlier attempt at
`APEX_CODE = FINEST` produced a truncated log).

**Result:** the failing transaction emits no usable log.
- Only a **505-byte** entry appears for the Opportunity operation under `saurabh.patil`:
  `CODE_UNIT_STARTED | [EXTERNAL] | limit check | Opportunity` → `EXECUTION_FINISHED`.
  No DML, no `FLOW_START_INTERVIEW`, no `FLOW_ELEMENT_ERROR`, no exception.
- The accompanying `/SBQQ/ServiceRouter` log (6,051 bytes) shows only the Contract trigger and our
  `Contract: Create` flow completing cleanly.
- No log anywhere contains `DUPLICATE_VALUE`, `FLOW_ELEMENT_ERROR` or `FLOW_ELEMENT_FAULT`.

Our platform-level `Flow_Log__c` error table also captures nothing, because the transaction rolls
back and takes the log rows with it. The error text survives **only** on the `SBQQ.ContractSave`
Visualforce page, which is not queryable — meaning this failure class is effectively invisible to
monitoring. One affected contract went four months before anyone noticed.

## 7. What we need from Support

1. **Decode the three Error IDs.** Which internal operation raised `DUPLICATE_VALUE`, and against
   which `OpportunityContactRole` (Opportunity Id, Contact Id, Role)? We cannot see inside the
   managed package.
2. **Explain 5(a).** Does the CPQ renewal process create `OpportunityContactRole` records
   independently of `SBQQ__DefaultRenewalContactRoles__c`? Disabling that field did not stop the
   duplicate, which we cannot reconcile with the documented behaviour.
3. **Explain section 6.** Why does this transaction produce no debug log despite active trace flags
   on both the initiating user and the executing user? Is renewal creation running in a context
   that trace flags cannot capture, and if so how should it be diagnosed?
4. **Recommend remediation** for the four contracts so the renewal Opportunities can be created
   without hand-building them and losing CPQ's subscription and quote linkage.

## 8. Environment notes

- Renewal Opportunity creation is consistently attributed to `CreatedBy = Saurabh Patil`
  regardless of who initiates it, and completes roughly 3–4 minutes after contract creation.
- Our `Opportunity_AfterUpdate_MasterFlow` (API name `Opportunity`, v32, RecordAfterSave on
  Opportunity) has a scheduled path offset 2 minutes after `LastModifiedDate`, which accounts for
  that lag.
- Our `Opportunity_Contact_Role_Check_for_Duplicate` flow (v9, active) deliberately **tolerates**
  duplicate contact roles: it logs a non-blocking warning and lets the save commit, leaving cleanup
  to an async reconciler. It does not throw. The `DUPLICATE_VALUE` in this case is therefore a
  platform-level DML rejection, not one of our validation flows.
