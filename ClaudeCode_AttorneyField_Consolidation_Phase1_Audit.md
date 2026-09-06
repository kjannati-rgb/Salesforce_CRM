# Account Attorney-Count Field Consolidation — Phase 1 Audit

**Date:** 2026-06-19
**Org audited:** `KJDEV` sandbox — `https://lawbusinessresearch--kjdev.sandbox.my.salesforce.com` (user `kamyar.jannati@lbresearch.com.kjdev`)
**Confirmed:** This is a **SANDBOX**, not production (`.sandbox.my.salesforce.com` domain + `.kjdev` username suffix). No writes were performed in this phase.

- **SURVIVOR (keep):** `Account.Number_of_Attorneys__c` — "Number of Attorneys", Number(18,0), component Id `00NTm000002XohdMAC`
- **RETIRE (remove):** `Account.of_Attorneys__c` — "ALM # of Attorneys", Number(18,0), component Id `00NPx00000ACARFMA5`
- **Do not touch:** `Account.Total_US_Attorneys__c` (`00NPx00000ACARDMA5`), `Account.Total_Non_US_Attorneys__c` (`00NPx00000ACARCMA5`)

---

## ⚠️ Critical context: the field names are reused on other objects

The two API names are **not unique to Account.** Tooling `CustomField` lookup returned:

| API name | Object | Component Id | In scope? |
|---|---|---|---|
| `Number_of_Attorneys__c` | **Account** | `00NTm000002XohdMAC` | ✅ survivor |
| `of_Attorneys__c` | **Account** | `00NPx00000ACARFMA5` | ✅ retire |
| `Number_of_Attorneys__c` | `SBQQ__Quote__c` | `00NPx00000AV8I7MAL` | ❌ different field |
| `Number_of_Attorneys__c` | `SBQQ__QuoteLine__c` | `00NTm000002Xow9MAC` | ❌ different field |
| `of_Attorneys__c` | **Opportunity** | `00NPx00000AUINvMAP` | ❌ different field |
| `ALM_of_Attorneys__c` | **Lead** | (separate) | ❌ substring match only |

Every reference below was scoped **strictly to the Account fields by component Id**, not by name. Two early grep hits were confirmed false positives: a Lead flexipage referencing `ALM_of_Attorneys__c` (substring of `of_Attorneys__c`) and a report type column `SBQQ__PrimaryQuote__c.Number_of_Attorneys__c` (the Quote field).

---

## Executive summary

`Account.of_Attorneys__c` has a **small, clean reference footprint** that is fully remediable:

- **2 formula fields** read it (need repointing to the survivor).
- **2 page layouts** display it (need the field item swapped to the survivor).
- **FLS** is granted across many profiles + permission sets (survivor needs FLS parity before cutover).
- **No** Apex, triggers, flows, processes, workflow field updates, approval processes, validation rules, LWC, Aura, email templates, custom metadata, field sets, list views, compact layouts, web links, or CPQ rules reference it.

**Integration-fed finding:** **No** — there is no automated inbound integration, managed package, or named credential writing to `of_Attorneys__c`. It is a plain field **maintained manually by the ALM/Law.com "data team" (human users)**, likely via UI edits and/or periodic ALM data loads. See the dedicated section below. → Consolidation can proceed; we do **not** need to flip the survivor or keep both, but the data-stewardship process must be redirected to the survivor (verified in PROD).

---

## Methodology (4 independent sources, cross-checked)

1. **Tooling API dependency graph** — `MetadataComponentDependency` filtered by `RefMetadataComponentId` (the `RefMetadataComponentName` field is **not filterable**; the Id-based query is the authoritative one).
2. **Full-text grep of retrieved metadata** — retrieved into temp dirs (outside the working tree to avoid clobbering uncommitted changes) and grepped with word boundaries: `CustomObject:Account` (fields, field sets, list views, compact layouts, web links, validation rules), the two flagged layouts, **all** ApexClass + ApexTrigger, **all** LWC + Aura bundles, **all** CustomMetadata, **all** EmailTemplate.
3. **CPQ rule data records** — described each rule object to get the real column names, then queried the field-reference columns.
4. **FLS** — queried `FieldPermissions` directly (the dependency graph does **not** reliably capture FLS).

---

## Findings by component type

### 1. Formula fields — REPOINT REQUIRED (2)

Both are Account formula fields that bucket the attorney count. Source of truth: org (Tooling `CustomField.Metadata`); also visible in `tmp-attorney-audit/.../objects/Account.object`.

| Field | API name | Component Id | How it uses `of_Attorneys__c` | Remediation |
|---|---|---|---|---|
| ALM Industry Category | `Industry_Category__c` | `00NPx00000ACEcZMAX` | Text formula: for Law Firm accounts, buckets `of_Attorneys__c` at ≥151 / ≥71 / ≥6 / ≤5 → Large Law / Mid-Market Law / SMB Law / Solo Practitioner Law | Replace all `of_Attorneys__c` tokens with `Number_of_Attorneys__c` |
| ALM Industry Category Code | `ALM_Industry_Category_Code__c` | `00NPx00000CadqMMAR` | Text formula: for Law Firm accounts, buckets `of_Attorneys__c` at ≥151 / ≥71 / ≥6 → L / M / S / Z | Replace all `of_Attorneys__c` tokens with `Number_of_Attorneys__c` |

**Consistency note (not a blocker):** the `Account Update Industry Category` **flow** already computes the same buckets from the **survivor** `Number_of_Attorneys__c` and writes the result to `Industry_Category_txt__c`. So the org currently has the formula fields reading the *retire* field while the flow reads the *survivor*. Repointing the two formulas **removes** this latent inconsistency. (Separately: the flow only fires when `Industry_Data_Provider__c`, `Industry_Category_Override__c`, or `Industry_ALM__c` changes — not when attorney count changes — so `Industry_Category_txt__c` can already be stale. Out of scope here; flagging for awareness.)

### 2. Page layouts — SWAP FIELD ITEM (2)

Both place `of_Attorneys__c` as an editable item, and **neither currently shows the survivor** — so the field must be *swapped*, not merely deleted, or users lose the attorney count from the page.

| Layout (fullName) | Component Id | Local file (retrieved) | Remediation |
|---|---|---|---|
| `Account-Firm Layout` | `00h6g0000086fYTAAY` | `tmp-attorney-layouts/.../layouts/Account-Firm Layout.layout` (line ~385) | Change `<field>of_Attorneys__c</field>` → `<field>Number_of_Attorneys__c</field>` |
| `Account-Office Layout - Data Team` | `00h4L000003YiVcQAK` | `tmp-attorney-layouts/.../layouts/Account-Office Layout - Data Team.layout` (line ~386) | Same swap |

### 3. Field-Level Security — PARITY REQUIRED before cutover

`of_Attorneys__c` has FLS in **many profiles** (profile-owned permission sets) plus these named permission sets; the survivor must have **≥** the retire field's access so no one loses the ability to read/edit attorney count after cutover.

| Permission set | `of_Attorneys__c` | `Number_of_Attorneys__c` (survivor) | Gap to fix |
|---|---|---|---|
| ALM fields | R | R | none |
| **ALM fields - Data team** | **R/W** | **R only** | grant survivor **Edit** |
| **Additional Account Permission for ALM CS team** | **R/W** | **(not present)** | add survivor **R/W** |
| Data Cloud Salesforce Connector | R | R | none (consumer — see integration section) |
| Law.com Account Change Permission | R | R | none |
| Sergio permissions migrate | R/W | R/W | none |
| (many profile-owned perm sets) | R/W | R/W | spot-check parity in PROD |

> The full per-profile FLS list differs slightly between sandbox and PROD; in Phase 3 we generate the survivor-FLS delta from the **PROD** `FieldPermissions` snapshot.

### 4. References that already use the SURVIVOR — NO ACTION

From the dependency graph on `Number_of_Attorneys__c` (`00NTm000002XohdMAC`):

- **Flow** `Account Update Industry Category` (3 versions: `301Px00000WgfagIAB`, `301Px00000X1zd1IAB`, `301Px00000XKL75IAH`) — reads survivor. ✅
- `SBQQ__Quote__c.Number_of_Attorneys__c` (`00NPx00000AV8I7MAL`) and `SBQQ__QuoteLine__c.Number_of_Attorneys__c` (`00NTm000002Xow9MAC`) — these Quote/QuoteLine fields reference the Account survivor (CPQ field-default/cross-object). ✅ Leave as-is.
- `Number_of_Attorneys_in_Firm` (`00NTm000002kEmnMAE`) — references survivor. ✅
- A list view on Account includes `Number_of_Attorneys__c` as a column. ✅

### 5. Areas checked and CLEAN (zero references to either Account field)

| Area | Method | Result |
|---|---|---|
| Apex classes + triggers (all) | retrieved all, grep | **0** (no compiled or dynamic-string refs) |
| LWC + Aura bundles (all) | retrieved all, grep | **0** |
| Email templates (all) | retrieved all, grep | **0** |
| Custom metadata (all types) | retrieved all, grep | **0** |
| Validation rules, field sets, list-view *filters*, compact layouts, web links/custom buttons | in `Account.object`, grep | **0** referencing the retire field |
| Workflow rules / field updates, approval processes, processes (PB) | dependency graph | **0** |
| CPQ price/product rules | data query (see below) | **0** (but org is empty — see caveat) |

### 6. CPQ — VERIFIED CLEAN in production ✅

The dependency graph and "Where is this used?" cannot see CPQ, because CPQ stores field references as **text on data records**. I described each rule object to get the real column names (this CPQ build is variable/formula-based), then queried for any attorney reference.

- **KJDEV sandbox has 0 CPQ rule records** — so the sandbox check was clean only by virtue of being empty. The real check was run against **production (`LBR_PROD`, `lawbusinessresearch.my.salesforce.com`)** — read-only.
- **Production result (scanned 2026-06-19):** **No attorney-field references in any price or product rule.**

| CPQ object | PROD records | Attorney field refs |
|---|---|---|
| `SBQQ__PriceCondition__c` | 8,865 | 0 (filterable cols + `SBQQ__TestedFormula__c` / `SBQQ__FilterFormula__c` long-text grepped client-side) |
| `SBQQ__PriceAction__c` | 3,975 | 0 (filterable cols + `SBQQ__Formula__c` long-text grepped client-side) |
| `SBQQ__PriceRule__c` | 1,996 | 0 (no field columns; logic lives in conditions/actions) |
| `SBQQ__ErrorCondition__c` | 349 | 0 real (see false positive) |
| `SBQQ__ProductRule__c` | 94 | 0 |
| `SBQQ__SummaryVariable__c` | 13 | 0 (covers variable-based references) |
| `SBQQ__LookupQuery__c` | 2 | 0 |

Columns checked: picklists `SBQQ__Field__c`, `SBQQ__TestedField__c`, `SBQQ__LookupField__c`, `SBQQ__AggregateField__c`, `SBQQ__ConstraintField__c`, `SBQQ__FilterField__c`, `SBQQ__SourceLookupField__c`, `SBQQ__Lookup*Field__c`; strings `SBQQ__ValueField__c`, `SBQQ__Value__c`, `SBQQ__*Object__c`, `SBQQ__*Value__c`; and the non-filterable long-text formula columns `SBQQ__TestedFormula__c`, `SBQQ__FilterFormula__c`, `SBQQ__Formula__c` (selected and grepped client-side across all rows).

**Only "Attorney" hit (false positive):** ErrorCondition `a0IPx000006kYrFMAU` (#000410, rule "Compass Included with Law.com") filters `ALM_Account_Segment__c = "Courts and District Attorney Offices"` — a segment *value*, not an attorney field.

**Conclusion:** retiring `of_Attorneys__c` will not break any CPQ price or product rule.

### 6b. CPQ Quote Templates — VERIFIED CLEAN in production ✅

Quote templates are the same blind spot as rules (field references stored as text on template records — line-column field names, HTML content blocks, terms text/conditions — invisible to the dependency graph and "Where is this used?"). Described each template object for its real columns, then scanned production (`LBR_PROD`) read-only.

| Template object | PROD records | Attorney **field** references |
|---|---|---|
| `SBQQ__LineColumn__c` (line-item table columns) | 4,519 | 0 (`SBQQ__FieldName__c`, `SBQQ__ColumnHeadingField__c`, `SBQQ__ConditionalPrintField__c`) |
| `SBQQ__TemplateContent__c` (HTML content) | 463 | **1 block** — `{!quote.Number_of_Attorneys__c}` (see below) |
| `SBQQ__QuoteTemplate__c` (group/sort/subtotal/total/discount fields + `SBQQ__TermsConditions__c`) | 938 | 0 |
| `SBQQ__TemplateSection__c` (conditional-print/filter/group/rollup fields + filter value) | 3,902 | 0 |
| `SBQQ__QuoteTerm__c` (`SBQQ__Body__c` + `SBQQ__AdvancedCondition__c`) | 277 | 0 (15 "attorneys' fees" *prose* hits in Body; AdvancedCondition = 0) |

Long-text columns (`SBQQ__Markup__c`, `SBQQ__RawMarkup__c`, `SBQQ__Body__c`, `SBQQ__AdvancedCondition__c`, `SBQQ__TermsConditions__c`) were selected and grepped client-side across all rows.

**The only attorney *field* reference:** template content `a1XPx000003uBjqMAE` ("2. Authorized Users for Digital Products - Law Firm") merges **`{!quote.Number_of_Attorneys__c}`**. This is the **Quote** field `SBQQ__Quote__c.Number_of_Attorneys__c`, a Text **formula**:

```
if(SBQQ__Account__r.Ultimate_Account__r.Number_of_Attorneys__c = 0, "",
   text(SBQQ__Account__r.Ultimate_Account__r.Number_of_Attorneys__c))
```

→ it resolves to the **survivor** `Number_of_Attorneys__c` on the Account's **Ultimate Account (Firm)** — **not** `of_Attorneys__c`. So no template touches the retire field.

> **Data-migration implication (Phase 2/PROD):** generated quotes already read the **survivor** (at the Firm/Ultimate-Account grain). If firms today have `of_Attorneys__c` populated but `Number_of_Attorneys__c` blank, those quotes already render blank — the `of_Attorneys__c → Number_of_Attorneys__c` migration must therefore populate the survivor **on Ultimate Account (Firm) records**, not only office-level Accounts.

### 7. Reports & Dashboards — dependency-graph clean; full grep impractical

The dependency graph shows **no** report/dashboard reference to either Account field. However the org has **6,424 reports / 360 dashboards** — too many to retrieve and full-text grep, and report field-filter usage is the dependency graph's least reliable area. **PROD action:** confirm via the field's Setup **"Where is this used?"** (which *does* cover reports), or retrieve only reports in ALM/Firm/Office/segmentation folders and grep. Risk rated **LOW** (plain field; equivalent survivor logic already exists).

---

## Integration-fed determination: is `of_Attorneys__c` written by an integration?

**Finding: No automated integration / managed package / named credential writes it. It is human-maintained by the ALM/Law.com data team.**

Evidence:

1. **Field shape** — plain `Number(18,0)`: `formula = null`, no roll-up (`summaryOperation = null`), no default, `externalId = false`, no help text. It does not self-calculate, so values come from outside metadata (manual entry or data load).
2. **No automation writes it** — dependency graph shows **no** flow, process, workflow field update, or Apex referencing it; the all-Apex grep (compiled **and** dynamic string literals) is also clean. No custom convert code (`LeadConvertInvocable`, `SmartConvertController`) touches it.
3. **No managed package** — every dependency record has a `null` namespace; no packaged component references it.
4. **Who can write it = humans, not a system user.** Edit FLS is concentrated in `ALM fields - Data team` (R/W), `Additional Account Permission for ALM CS team` (R/W), and `Sergio permissions migrate` (R/W). The ALM/Law.com permission sets are assigned to **7 active Standard (human) users** — ALM/Law.com staff (`@alm.com`, `@lbresearch.com`), e.g. Cindy Leung, Kieran Hansen, Ashton Thompson, Cayla Vichot, Jessica Silveira, Khris Fenton, Shawn Harlan. **No integration/automated-process user** is assigned.
5. **`Data Cloud Salesforce Connector`** perm set has **Read only** on both fields → Salesforce Data Cloud is a **downstream consumer** (ingests the field), not a writer.

**Implications for retirement:**
- Safe from a "live integration will break" standpoint — no automation/package/named credential to flip or preserve.
- The **manual/data-load stewardship** that currently targets `of_Attorneys__c` must be **redirected to `Number_of_Attorneys__c`** going forward.
- **Verify in PROD before deleting:** (a) field history / `LastModifiedBy` on populated Accounts to confirm who/what actually writes it; (b) ask the ALM data team whether any Data Loader/ETL job maps an ALM file column to `of_Attorneys__c`; (c) whether Data Cloud ingests `of_Attorneys__c` (remap the data stream to the survivor).

---

## Residual items requiring PROD verification or a manual step

1. **PROD data migration** (not applicable in sandbox — Account has 0 records here). **Production data profile (read-only, 2026-06-19):** of 738,825 Accounts, RETIRE is populated on 29,684 and SURVIVOR on 29,779. Where **both** are populated (29,575), **28,953 match (97.9%)** and **622 differ**. **109** have RETIRE-only (survivor blank → must copy before deprecation); 204 have SURVIVOR-only. The two fields are ~98% redundant duplicates.
   - **Migration rule (needs data-owner sign-off):** set `Number_of_Attorneys__c := of_Attorneys__c` for the **109** survivor-blank records, and — recommended — for the **622** conflicts (RETIRE is the ALM-maintained source, and this keeps the `Industry_Category__c` / `ALM_Industry_Category_Code__c` repoint behavior-neutral, since those formulas read the retire value today). Conflicts often repeat across offices of the same firm → migrate at the **Ultimate Account (Firm)** grain (see §6b). Alternative: fill only the 109 blanks and accept that industry categorisation shifts for the 622 after repointing.
2. ~~**CPQ rules in PROD** — re-run the scan~~ ✅ **Done 2026-06-19** — verified clean in `LBR_PROD` (section 6).
3. **Reports/dashboards in PROD** — confirm via "Where is this used?" / targeted grep (section 7).
4. **Lead conversion mapping** — the Lead field `ALM_of_Attorneys__c` exists; native lead-conversion field mappings are **not** visible to the dependency graph or to grep. Manually confirm in **Setup → Object Manager → Lead → Map Lead Fields** whether `ALM_of_Attorneys__c` maps to `Account.of_Attorneys__c`; if so, remap to `Number_of_Attorneys__c`. (No Apex/flow performs this copy, so the native map is the only possible vector.)
5. **Redirect ALM data-team stewardship / Data Cloud stream** to the survivor (see integration section).

---

## Next step

Phase 1 is complete and stops here for your **sign-off**. On approval I will produce the **Phase 2 ordered remediation + rollback plan** (still no writes), covering: FLS parity → formula repoints → layout swaps → PROD data migration → deprecate → (separately confirmed) delete.
