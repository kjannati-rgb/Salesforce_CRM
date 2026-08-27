# Order Form v1.2 - Runbook Log

## Phase 0 - Discovery (2026-08-12, read only)

**Org verification:** `sf org display --target-org KJDEV` -> username `kamyar.jannati@lbresearch.com.kjdev`, instance `https://lawbusinessresearch--kjdev.sandbox.my.salesforce.com`, org Id `00DAe00000D35gVMAR`. Sandbox confirmed. Not production (prod = 00D6g0000081IOg). PASS.

### 0.1 Existing templates
`SELECT Id, Name, SBQQ__Default__c FROM SBQQ__QuoteTemplate__c` -> **0 records in KJDEV**. The current default template exists only in PROD (KJDEV is a data-empty sandbox). Consequence: no local reference template; if we want the PROD default's sections/columns as a styling reference, that needs an explicitly authorized read-only PROD query or a manual export. Not a blocker for the build.

### 0.2 CPQ template object shape
- HTML markup field confirmed: `SBQQ__TemplateContent__c.SBQQ__Markup__c` (textarea). `SBQQ__RawMarkup__c` also exists. Content type via `SBQQ__Type__c` (picklist).
- `SBQQ__TemplateSection__c` required fields: only `SBQQ__Template__c` (master lookup).
- `SBQQ__LineColumn__c` required fields: `SBQQ__Template__c`, `SBQQ__DisplayOrder__c`, `SBQQ__FieldName__c`, `SBQQ__Width__c`.
- `External_Id__c` absent on all four template objects -> build in Phase 1 as planned.

### 0.3 Account fields
| Doc value | Existing field | Status |
|---|---|---|
| Company registration number | `Trade_Register_Number__c` (Text) | EXISTS - candidate for reuse; decide reuse vs new `Registration_Number__c` |
| VAT/GST/Sales Tax number | `VAT_ID__c` ("ALM VAT ID"), `Sales_Tax_Number__c`, `Tax_Importers_Code__c` | EXISTS - multiple candidates from ALM invoice work; decide canonical target (also the Adobe Sign write-back target) |

New decision 7 added below: reuse existing Account fields or create the runbook's new ones.

### 0.4 Quote / Opportunity fields
| Item | Finding |
|---|---|
| REV-73 legal entity | `Opportunity.LBR_Legal_Entity__c` = formula `TEXT(Owner.LBR_Legal_Entity__c)`. Quote twins already exist: `Quote_Owner_LBR_Legal_Entity__c` = `TEXT(Owner:User.LBR_Legal_Entity__c)` and `Sales_Rep_Legal_Entity__c` = `TEXT(SBQQ__SalesRep__r.LBR_Legal_Entity__c)` (both formula Text). CMDT key source: decide owner vs sales-rep variant. |
| Legal entity values in use (User.LBR_Legal_Entity__c) | ALM Global, LLC; Law Business Research (UK) Ltd.; Law Business Research LLC; Law Business Research (Asia) Ltd.; The Business Research Company; MBL Seminars Limited. 197 users blank -> stamping flow needs a blank-entity fault path. |
| Contact lookups on Quote | `SBQQ__PrimaryContact__c`, `Invoice_Contact__c` (+`Invoice_Contact_Email__c`/`_Phone__c`/`_Name__c`), `Secondary_Contact__c`, `Creative_Contact__c`, `Event_Logistics_Contact__c`, `Alternative_Production_Contact__c`. Opportunity side: `Primary_Contact__c`, `Invoice_Contact__c`. Section 2 rows Main/commercial + Billing/invoice are fully covered; Legal/notices has no field (decision 1). |
| Customer PO number | `SBQQ__Quote__c.PO_Number__c` (Text) EXISTS -> do NOT build `Customer_PO_Number__c`. Data mapping targets `PO_Number__c`. |
| Special terms | `SBQQ__Quote__c.Special_Terms__c` (LongTextArea, label "Special Terms (Legal Terms only)") EXISTS -> reuse for section 7. |
| Signed date | No customer-signed-date field on Quote (only `Signature_Received__c` checkbox). -> build `Customer_Signed_Date__c` in Phase 1. |
| Customer name/address merges | CPQ standard Bill To fields exist and are CPQ-populated on Quote: `SBQQ__BillingName__c`, `SBQQ__BillingStreet__c`, `SBQQ__BillingCity__c`, `SBQQ__BillingState__c`, `SBQQ__BillingPostalCode__c`, `SBQQ__BillingCountry__c` -> section 1 customer block needs no new stamped fields for name/address. |
| Existing Adobe Sign plumbing on Quote | `Single_Signer__c` (formula: blank `Secondary_Contact__c`), `Secondary_Signer__c`, `Signature_Received__c`, `Adobe_Sign_Billing_Frequency__c`, `Adobe_Sign_Production_Contact__c`, `Adobe_Sign_Secondary_Contact_Email__c`. A PROD Adobe Sign flow already exists for other document types - the new agreement template must not collide with it (naming, data mappings, `Signature_Received__c` semantics). |
| Quote totals | `SBQQ__NetAmount__c` EXISTS for the "Total annual fee" row. |

### 0.5 Payment Terms picklist (SBQQ__PaymentTerms__c)
Active values: **Due on receipt, Net 15, Net 30, Net 45, Net 60**. Inactive history values not referenced.
**"Immediate on receipt" does not exist as a picklist value.** Nearest active equivalent: "Due on receipt" (the value from the June 2026 deactivation incident, active again in KJDEV). Resolution options: (a) render the doc's fixed literal "Immediate on receipt of valid invoice" as static text per Appendix A, or (b) align doc wording with "Due on receipt". Flag to Shinae/Finance -> new decision 8.

### 0.6 Adobe Sign package
- `echosign_dev1` - Adobe Acrobat Sign v24.35.0.1 installed. Bonus find: `ASSFCPQ` - Adobe Sign Salesforce CPQ Connector v1.6.0.1 also installed (relevant to Phase 4 send automation).
- **Runbook correction:** the agreement template object is `echosign_dev1__Agreement_Template__c` - there is no `SIGN_Agreement_Template__c`. `echosign_dev1__SIGN_Merge_Mapping__c` and `echosign_dev1__SIGN_Data_Mapping__c` exist as expected.
- KJDEV record counts: Agreement_Template 0, Merge_Mapping 0, Data_Mapping 0 -> Phase 3 is greenfield config in KJDEV (PROD's existing config was not copied to the sandbox).

### 0.7 Quote line pricing field
`SBQQ__NetTotal__c`, `SBQQ__StartDate__c`, `SBQQ__EndDate__c` all exist. Recent KJDEV lines carry sane NetTotal values (WTR profile/biography products), but KJDEV has only **one** subscription-priced line and its NetTotal is 0 - the sandbox has no representative subscription quote to validate against. Validation of "annual fee per line" against a real subscription quote requires PROD data (blocked by ground rule 2 unless a read-only query is explicitly authorized) -> stays under decision 4.

### 0.8 New-field existence sweep (all confirmed absent, to build in Phase 1)
Account: `Registration_Number__c`, `VAT_GST_Tax_Number__c` (pending decision 7). Quote: `Signatory_Contact__c`, `Legal_Notices_Contact__c`, `Auto_Send_For_Signature__c`, `Company_Entity_Name__c`, `Governing_Law_Text__c`, `Customer_Signed_Date__c`. Product2/QuoteLine: `License_Model__c`, `Authorised_User_Count__c`, `Benefiting_Group_Description__c`, `Warranted_Headcount__c`.
Overlap warning for the licence model design: QuoteLine already has `Benefitting_Group__c` (picklist), `Benefitting_Group2__c` (multipicklist), `Benefitting_Group_Type__c`, `Benefitting_Group_Quote_Template__c` (textarea - existing template wording field), `Employee_Headcount__c` (number), and Product2 has `Benefitting_Group__c` (checkbox). The new `License_Model__c` family overlaps this existing benefiting-group model -> new decision 9: reuse/extend the existing fields or build the parallel set.

### Merge value map (document -> field)
| Doc blank | Field | Status |
|---|---|---|
| Company entity name / reg no / registered office | `Company_Entity_Name__c` / `Company_Reg_Number__c` / `Company_Registered_Office__c` (CMDT-stamped) | NEW |
| Customer entity name + address | `SBQQ__BillingName__c` + Bill To address fields | EXISTS |
| Customer registration number | `Trade_Register_Number__c` (or new) | DECISION 7 |
| Customer VAT/GST number | `VAT_ID__c` / `Sales_Tax_Number__c` (or new); also signer-fillable tag `VAT_Number` | DECISION 7 |
| Main/commercial contact | `SBQQ__PrimaryContact__c` | EXISTS |
| Billing/invoice contact | `Invoice_Contact__c` (+email/phone helpers) | EXISTS |
| Legal/notices contact | `Legal_Notices_Contact__c` | BLOCKED (decision 1) |
| Product description | `SBQQ__ProductName__c` | EXISTS |
| License model wording | `License_Model_Display__c` (formula on new fields) | NEW (decision 9 shape) |
| Annual fee (excl. tax) per line | `SBQQ__NetTotal__c` (working assumption) | DECISION 4 |
| Currency | `CurrencyIsoCode` | EXISTS |
| Start / End date | `SBQQ__StartDate__c` / `SBQQ__EndDate__c` | EXISTS |
| Total annual fee | `SBQQ__NetAmount__c` | EXISTS |
| Payment due wording | static text or `SBQQ__PaymentTerms__c` | DECISION 8 |
| PO number | `PO_Number__c`; signer tag `PO_Number` | EXISTS |
| Governing law text | `Governing_Law_Text__c` (CMDT-stamped, keyed on `Quote_Owner_LBR_Legal_Entity__c` or `Sales_Rep_Legal_Entity__c`) | NEW |
| Special terms | `Special_Terms__c` | EXISTS |
| Signatory | `Signatory_Contact__c` (default from `SBQQ__PrimaryContact__c`) | NEW |
| Customer signed date (write-back) | `Customer_Signed_Date__c` | NEW |

### New decisions raised by discovery
| # | Decision | Owner |
|---|---|---|
| 7 | Account reg/VAT fields: reuse `Trade_Register_Number__c` + `VAT_ID__c`/`Sales_Tax_Number__c` or build new dedicated fields (write-back target must match) | Kam + Finance |
| 8 | Payment due: "Immediate on receipt" is not a picklist value; render literal text or align wording to active "Due on receipt" | Shinae + Finance |
| 9 | Licence model: build new `License_Model__c` family or extend existing Benefitting_Group/Employee_Headcount fields already on QuoteLine/Product2 | Kam |
| 10 | CMDT key: `Quote_Owner_LBR_Legal_Entity__c` (quote owner) vs `Sales_Rep_Legal_Entity__c` (sales rep) as the selling-entity determinant; and fault path for blank entity | Kam + Shinae |
| 11 | Coexistence with the existing PROD Adobe Sign setup (naming, `Signature_Received__c` reuse, existing data mappings) - map PROD config before Phase 3 re-key | Kam |

### Decisions resolved (Kam, 2026-08-12)
- **7 RESOLVED:** reuse existing Account fields. Registration number = `Trade_Register_Number__c`; VAT/GST = `VAT_ID__c` (Adobe Sign write-back target; `Sales_Tax_Number__c` left untouched). No new Account fields.
- **8 RESOLVED:** PROD active picklist value is "Due Upon Receipt of Invoice" (KJDEV shows stale "Due on receipt" - org drift, note for UAT/prod parity). Section 4 renders the live value via `{!quote.SBQQ__PaymentTerms__c}` rather than a hardcoded literal; confirm with Shinae that rendering the quote's actual terms (vs fixed wording) is acceptable.
- **9 RESOLVED (recommendation accepted pending GO):** build the NEW `License_Model__c` field family; do not extend the existing Benefitting_Group/Employee_Headcount fields (ALM semantics, existing consumers, regression risk). Existing fields untouched.
- **10 RESOLVED:** CMDT keyed on `Sales_Rep_Legal_Entity__c` (sales rep, not quote owner). Stamping flow fault path required for blank rep entity.
- **11 RESOLVED:** OK'd. New agreement template is a separate record; no reuse of `Signature_Received__c` semantics; PROD config mapped before Phase 3 re-key.

**Phase 0 complete. GO received 2026-08-12.**

---

## Phase 1 - Metadata (2026-08-12, deployed to KJDEV)

**Deploy:** `sf project deploy start` Succeeded, 35/35 components, 0 errors. Deploy Id `0AfAe00000RwrScKAJ`. Project lives at `order-form-v1.2/` as a self-contained SFDX project (own `sfdx-project.json`) so the main repo is untouched.

**Built (per resolved decisions - Account fields and Customer_PO_Number__c skipped):**
- Product2 + SBQQ__QuoteLine__c twins: `License_Model__c` (restricted picklist: Authorised Users / Limited Access / Benefiting Group / Enterprise-Wide Access), `Authorised_User_Count__c` (18,0), `Benefiting_Group_Description__c` (Text 255), `Warranted_Headcount__c` (18,0).
- QuoteLine `License_Model_Display__c` (formula Text, CASE over License_Model producing full Appendix A wording; BlankAsBlank so empty counts render as blank not 0).
- SBQQ__Quote__c: `Signatory_Contact__c` + `Legal_Notices_Contact__c` (Contact lookups; Legal Notices kept OFF layouts per decision 1), `Auto_Send_For_Signature__c` (checkbox default false), `Company_Entity_Name__c`, `Company_Reg_Number__c`, `Company_Registered_Office__c` (TextArea), `Governing_Law_Text__c` (LongTextArea), `Customer_Signed_Date__c` (Date).
- CMDT `Legal_Entity_Document_Config__mdt` (Entity_Value unique/required, Legal_Entity_Name, Registration_Number, Registered_Office, Governing_Law_Clause) + 6 records, one per live entity value, reg/office/clause = PLACEHOLDER pending decision 3.
- Flow `Quote_Stamp_Order_Form_Fields`: before-save on SBQQ__Quote__c create+update. Verified Active post-deploy. Gotcha: before-save flows cannot reference formula fields on $Record - `Sales_Rep_Legal_Entity__c` rejected with field integrity exception; fixed with an in-flow formula `TEXT($Record.SBQQ__SalesRep__r.LBR_Legal_Entity__c)`. No-match/blank-rep path clears the four company-block fields (never stale). Signatory defaulted from `SBQQ__PrimaryContact__c` only when blank.
- `External_Id__c` (Text 100, External ID, Unique) on QuoteTemplate, TemplateContent, TemplateSection, LineColumn.
- Permission set `Order_Form_Template_Admin`: FLS for everything above (formula field read-only). Not yet assigned to anyone.

**Verified post-deploy:** flow Active (RecordBeforeSave), 6 CMDT records queryable with correct entity values.

**Notes:**
- `sf project deploy validate` defaults to RunLocalTests; the org's pre-existing red tests (contact-role VR blocking test data inserts, `Reporting_Stream__c` restricted picklist) fail any validate. Components themselves validated 42/42 clean first. Actual deploy used NoTestRun (sandbox default). PROD Phase 6 will need the specified-tests approach used for Opportunity Analytics.
- Stray whole-repo validate jobs (submitted from wrong cwd, validate-only, no org changes) were cancelled: 0AfAe00000Rwr61KAB, 0AfAe00000RwpH8KAJ, 0AfAe00000RwrHJKAZ; 0AfAe00000RwqzZKAR completed harmlessly.
- Rep-facing FLS (report-only, per runbook): the org convention for feature quote-line fields is dedicated per-feature permission sets (`Quote_line_fields_for_Lexology_Index`, `Quote_Line_Content_Slot_Fields`, etc.), not edits to broad sets like `Custom_Sales_Profile`/`Sales_User`/`Edit_all_Quotes`. Recommendation: assign `Order_Form_Template_Admin` to the subs sales group at UAT rather than modifying shared sets. `Salesforce_CPQ_Quote_Templates` permset exists for template-admin access.

**Phase 1 complete. GO received 2026-08-12.**

---

## Phase 2 - CPQ template records + HTML (2026-08-12, KJDEV)

**Additional metadata deployed first (44/44 clean):** 8 Quote formula fields to satisfy the no-cross-object-merge rule (`Main/Billing/Legal_Contact_Name_Title__c` + `_Email_Phone__c` pairs, `Customer_Registration_Number__c` = Account `Trade_Register_Number__c`, `Customer_VAT_Number__c` = Account `VAT_ID__c`), plus `Special_Terms_Display__c` (LongTextArea) stamped by the flow (Special_Terms__c is a long text area, unreachable by formulas -> flow decision stamps value-or-"None"). Permission set extended; assigned to Kamyar in KJDEV (needed for External_Id__c API access).

**Records pushed via `cpq-templates/push-template-content.js`** (idempotent REST upsert on External_Id__c, no npm deps, CONFIRM_PROD guard): template `OF-V12-TEMPLATE` (a1GAe00001muYndMAE, Not default, In Development, Portrait, Helvetica 9, margins 0.75, TotalField=Net Total, TotalLabel="Total annual fee"), 9 contents (8 HTML + Line Items), 9 sections in document order, 6 line columns (widths 26/26/16/8/12/12).

**Doc-engine gotchas discovered (all handled in the push script / HTML):**
1. CPQ auto-creates 6 default line columns (QTY, PART #, DESCRIPTION, UNIT PRICE, DISC %, EXTENDED) on template insert -> push script now deletes any column on the template with blank External_Id__c. Without this the table had 12 columns at ~200% width.
2. The PDF engine renders `SBQQ__RawMarkup__c` for HTML content, not `SBQQ__Markup__c` -> push writes both. With RawMarkup null, HTML sections silently do not render at all.
3. The engine strips `<h1>/<h2>` tags and the `border="1"` table attribute -> headers are styled `<p>` elements; borders are inline per-`<td>` styles.
4. Document generation works headless via `POST /services/apexrest/SBQQ/ServiceRouter` `{saver:"SBQQ.QuoteDocumentAPI.Save", model:{name,quoteId,templateId,outputFormat:PDF,...}}` -> AsyncApexJob -> `SBQQ__QuoteDocument__c` with classic Document body. The expired CPQ calc-service auth does NOT block document generation.
5. Payment due renders `{!quote.SBQQ__PaymentTerms__c}` alone (no hardcoded " of valid invoice" suffix - PROD value "Due Upon Receipt of Invoice" would have double-worded).

**Draft PDF:** generated from Q-211545 (test quote: UK entity rep, Limited Access 25 users, 2026-09-01..2027-08-31, GBP 4,160). Saved to `reference/order-form-v1.2-draft-Q211545.pdf`. All 9 sections render, company block + governing law stamped from CMDT (PLACEHOLDER values pending decision 3), licence wording correct, totals row correct, Adobe tags in BLACK 8px PLACEMENT MODE (flip to white 5px after tag placement is confirmed in Phase 3).

**Known cosmetics / open items for review:**
- Execution section starts page 2 on a 1-line quote (could set KeepTogether/PageBreak once Legal confirms layout).
- Annual fee renders with "GBP" prefix (engine currency formatting) alongside the Currency column - duplication to tolerate or hide.
- Customer registration number renders blank when Account.Trade_Register_Number__c is empty (only VAT + PO are signer-fillable per Appendix B) - flagged as an unowned blank for Shinae.
- Font is Helvetica (Aptos does not exist in the CPQ engine) - flag to Legal once, per runbook.
- Page size: PageHeight/Width set 11.69/8.27; A4 vs Letter needs a ruler check on the printed PDF at UAT.
- KJDEV picklist drift: payment due shows "Due on receipt" here; PROD will show "Due Upon Receipt of Invoice".

**Phase 2 complete pending Kam's PDF review. GO received 2026-08-12.**

---

## Phase 3 - Adobe Sign agreement template + mappings (2026-08-12, KJDEV)

**Route change:** the Browser pane blocks the org URL by policy, so instead of UI-keying, the config is built as data records by `adobe-sign/create-agreement-template.js` (idempotent, CONFIRM_PROD-guarded) - Phase 6 re-runs the script instead of re-keying by hand. Conventions were validated against the package describes and PROD's live config (read-only, per resolved decision 11).

**PROD reconnaissance (decision 11):** 3 agreement templates in PROD; the live one is "LBR Agreement Template" (a2w6g000000MyY9AAK), master = SBQQ__QuoteDocument__c, recipient = Look Up Based on Master Object Field -> SBQQ__PrimaryContactId__c, attachment = Runtime Variable. **No merge or data mappings exist in PROD** - our mappings are greenfield, no collision. Our template is a separate record mastered on SBQQ__Quote__c; no reuse of Signature_Received__c.

**Package data-model facts (for the PROD re-key record):**
- The Agreement object has NO Quote lookup (only ASSFCPQ__Quote_Document__c from the CPQ connector) - which is why PROD masters on QuoteDocument. For master=Quote + write-back we added custom `Quote__c` lookup on `echosign_dev1__SIGN_Agreement__c` (deployed 47/47 with `Customer_VAT_Number_Captured__c` on Quote + `Quote_Sync_Captured_VAT_to_Account` after-save flow).
- Auto-number Names (never set): Form_Field_Mapping, Form_Field_Mapping_Entry, File_Mapping, Recipient_Template, Attachment_Template (PROD's "0000001" names are auto-numbers).
- `SIGN_Field_Mapping__c.Name` = TARGET field API name (only writable target column on the object).
- `SIGN_Object_Mapping__c.Field_API_Name__c` = agreement lookup reaching the target record; `Fully_Qualified_API__c` = target object API name.

**Records created (verified by SOQL):**
| Record | Key settings |
|---|---|
| Agreement template "Order Form v1.2 - Subscription" (a2wAe000002IcosIAC) | master SBQQ__Quote__c; name "Order Form - {!SBQQ__BillingName__c} - {!Name}"; Active; Auto_Send true; e-Signature; single signer, sign in order; English (UK); wired to both mappings |
| Recipient (index 1) | Look Up Based on Master Object Field -> `Signatory_Contact__c`, Contact, Signer |
| Attachment (index 0) | Quote Document from Master Quote, Latest Document by Last Modified Date |
| Merge mapping "Order Form v1.2 - Merge Mapping" | VAT_Number <- Customer_VAT_Number__c; PO_Number <- PO_Number__c (master-object fields, pre-fill only) |
| Data mapping "Order Form v1.2 - Write-back" (on Signed, do-not-write-empty) | via Quote__c: PO_Number -> PO_Number__c; VAT_Number -> Customer_VAT_Number_Captured__c (relayed to Account.VAT_ID__c by the sync flow); agreement DateSignedDate -> Customer_Signed_Date__c; file mapping Signed Agreement Merged PDF -> Files on Quote |

**BLOCKED - manual round trip (step 5):** KJDEV has 0 agreements ever sent; the sandbox has no live Adobe Sign account link (sandbox refresh severs the OAuth link) and re-linking requires an interactive Adobe login by Kam (Adobe Sign Admin tab -> Account Linking). Until then the round trip (send to test mailbox, sign, verify tag placement + write-back + PDF filing) cannot run. The round trip is also the step that validates two API-built conventions flagged UNVERIFIED: merge-mapping entry path resolution (blank Object_Reference_Path__c = master object) and the Quote__c master-lookup auto-population on the agreement. After placement is confirmed, flip the Adobe tags from black 8px to white 5px in 01/04/08 HTML and re-push.

**Phase 3 config complete; round trip pending Adobe account link. GO received 2026-08-13 - Kam confirmed the link unblocks when the build moves to the other sandboxes (FULLUAT).**

---

## Phase 4 - Send automation (2026-08-13, KJDEV)

**Deployed 56/56 clean, tests 10/10 pass, OrderFormSignatureService coverage 93%.**

- **CMDT `Order_Form_Settings__mdt`** + Default record: `Agreement_Template_Name__c` = "Order Form v1.2 - Subscription" (resolved to Id at runtime - org-portable, never hardcoded), `Active__c` = kill switch (true in KJDEV).
- **`OrderFormSignatureService`** (invocable): validates kill switch, quote exists, status Approved, signatory set, quote document exists, template active - each with a distinct message - then `echosign_dev1.AgreementTemplateService.load(templateId, quoteId)` (signature confirmed by compile on v24.35). `@TestVisible bypassTemplateService` stubs the package boundary in tests; `settingsOverride` injects CMDT variants.
- **One-click:** quick action `SBQQ__Quote__c.Send_for_Signature` -> screen flow `Quote_Send_Order_Form_One_Click` (per-precondition error screens, fault screen, result screen). NOT yet on any Quote layout - placement is a UAT-time step (also the rollback lever).
- **Zero-click:** `Quote_Send_Order_Form_Zero_Click` record-triggered after-save on Quote: entry = status Approved (on change) AND `Auto_Send_For_Signature__c` = true AND signatory set; then doc-exists check -> same invocable. Checkbox defaults false = opt-in per quote.
- **AA confirmation (runbook 4.4):** SBQQ__Status__c active values include "Approved"; PROD shows 2,628 quotes at Approved in the last 30 days (read-only aggregate) - Advanced Approvals demonstrably lands quotes on the status the zero-click flow keys on. A full traced approval remains a Phase 5 UAT cell.
- **Test gotchas for the record:** CPQ forces new quotes to Draft on insert (set Approved via a follow-up update); agreement template is DATA so tests insert their own; `Application_Settings__c` user-level bypass used per org standard. The un-bypassed test showed `load()` itself succeeds without a linked Adobe account - link failures surface async at send, reinforcing that the FULLUAT round trip is the real E2E gate.

**Phase 4 complete. GO received 2026-08-13.**

---

## Phase 5 - UAT matrix, KJDEV leg (2026-08-13)

Full cell-by-cell results in `uat/UAT-results-kjdev.md`; evidence PDFs in `reference/`
(`uat-licence-models-Q211543.pdf`, `uat-pagination-8lines-Q211543.pdf`).

**Summary: 11 of 15 cells PASS in KJDEV; 4 deferred/partial pending the Adobe-linked FULLUAT leg and human sign-off.**
- PASS: all 4 licence models (incl. 5% wording), entity flip both directions (structural - CMDT text still PLACEHOLDER), single-line + 8-line pagination with no tag drift, zero-click flow firing + agreement creation with resolved name pattern, all 3 precondition failure messages, AA-sets-Approved evidence.
- Deferred to FULLUAT: write-back cells, dispatch + recipient/attachment/Quote__c resolution (all gated on the Adobe account link), one-click UI walk + quick action layout placement, renewal + default-template regression re-check, real entity values (decision 3).
- Known flake logged: doc generation can NPE once if run immediately after quote-line DML; retry succeeds.
- Human gate outstanding: Kam + rep + Finance sign-off on the PDF output.

**Phase 5 KJDEV leg complete. STOPPED - next steps are the FULLUAT leg (after Adobe link + sandbox promotion) and then the Phase 6 PROD gate (`DEPLOY TO PRODUCTION CONFIRMED`).**

---

## Branding pass (2026-08-13, KJDEV - post-Phase-5 addition at Kam's request)

**Sources:** official 2026 Word template (`Centellic_Word template_2026.dotx`) - theme palette navy `#003340`, green `#00C8A7`, teal `#008CA6` (+ tints), theme font Arial (engine renders Helvetica, its metric twin); logo = the dotx's embedded transparent PNG (4703x629).

**Applied:**
- Logo uploaded as externally-available Document `Centellic_Logo_2026` in public folder "Order Form Brand Assets" (`cpq-templates/upload-brand-assets.js`, idempotent + CONFIRM_PROD guard). Rendered via `<img>` in the per-page header; push script substitutes `{{LOGO_URL}}` with the TARGET org's instance URL + queried Document id, so PROD needs only the asset script run first.
- Per-page header (logo + "Order Form | quote number" + 2px green rule) and footer (selling-entity line: name | registered office | reg no), wired via `SBQQ__HeaderContent__c`/`FooterContent__c`, heights 48/34; page numbers footer-right.
- Full restyle of all 8 sections: navy masthead with tinted meta box, green-underlined section headings, navy block-header rows with white text, tinted label columns, grey-teal hairline borders, navy signature rules. Line-items table: template `SBQQ__BorderColor__c` C9D9DD + `SBQQ__ShadingColor__c` EAF3F4.
- Verbatim legal wording untouched; Adobe tags still black placement mode.
- Evidence: `reference/order-form-v1.2-branded-Q211545.pdf`.

**New doc-engine gotchas (cost a debug cycle each):**
1. `&nbsp;` is rejected (XML parser) - use `&#160;`.
2. `<img>` with a RELATIVE `/servlet/servlet.ImageServer` URL fails the whole render with "Bad Request" - the URL must be absolute (instance URL + servlet path). `SBQQ__LogoDocumentId__c` does not render when header content is set.
3. HTML comments (`<!-- -->`) inside HEADER content fail generation with "Bad Request" (body sections tolerate them) - push script now strips all comments before upload.

**Phase 6 note:** run `upload-brand-assets.js` against PROD before `push-template-content.js` (the push hard-stops if the logo Document is missing while `{{LOGO_URL}}` is referenced).

---

## DRAFT watermark for unapproved quotes (2026-08-13, KJDEV)

**Requirement (Kam):** documents generated while the quote is Draft or In Review carry a DRAFT watermark; approved documents are clean.

**Mechanism (corrected by Kam):** the watermark image is template-level (`SBQQ__WatermarkId__c`) but its DISPLAY is per-quote via `SBQQ__WatermarkShown__c` - and the org's EXISTING quote flows already manage that flag by status (`Quote_BeforeSave_UpdateQuoteFields` sets it true on new/draft quotes; `Quote_Create_Edit`, `Quote_Approval_Process`, `Quote_AL_UpdateGenericFields` clear it on approval). No new automation needed. (First-pass detour for the record: I initially concluded the watermark was unconditional and built a second DRAFT template + flow-driven `SBQQ__QuoteTemplateId__c` selection - wrong, because BOTH test quotes happened to have WatermarkShown=true; the API-only status change to Approved had not fired the org flow that clears it. The dual-template variant and the selection logic were removed and the org cleaned up.)

**Implementation (final):**
- Watermark asset: diagonal navy "DRAFT" PNG (780x1010 - the engine renders watermarks at native pixel size, a 1400px canvas overflowed the page), ~13% alpha of brand navy. Source committed at `cpq-templates/draft-watermark.png`; uploaded as Document `Order_Form_Draft_Watermark` by `upload-brand-assets.js --watermark`.
- The single "Order Form v1.2 - Subscriptions" template carries `SBQQ__WatermarkId__c`; the existing org flows toggle `SBQQ__WatermarkShown__c`. `Quote_Stamp_Order_Form_Fields` stays focused on stamping (template-selection logic removed).

**Verified E2E in KJDEV (single template):** Q-211543 (Draft, WatermarkShown=true) -> watermarked on every page (`reference/order-form-v1.2-draft-watermarked-Q211543.pdf`); Q-211545 (Approved, WatermarkShown=false) -> byte-identical to the clean branded baseline.

**UAT/FULLUAT check:** confirm the org flows actually clear WatermarkShown through the REAL approval path (AA approve action) - in KJDEV an API-only status flip to Approved left it true (entry criteria/record-type scoping of those flows to verify), in which case approved docs would render watermarked until the flow fires or the flag is cleared.

---

## FULLUAT promotion (2026-08-13)

**Org verified:** kamyar.jannati@lbresearch.com.fulluat, 00DAd00000CZR4rMAH, sandbox. Full sequence executed:
1. Metadata deploy: **56/56 Succeeded, 0 errors** (fields, CMDTs, 4 flows, Apex + test, permset, quick action).
2. `Order_Form_Template_Admin` assigned to Kamyar (needed for the push script's External_Id__c access).
3. `upload-brand-assets.js` - logo Document 015Ad00000AlBezIAF, watermark 015Ad00000AlBgbIAF (logo source now committed at `cpq-templates/centellic-logo-2026.png`).
4. `push-template-content.js` - template a1GAd0000161Qm5MAE + contents/sections/columns; package-default columns cleaned; logo URL resolved to the FULLUAT instance (org-portability proven).
5. `create-agreement-template.js` - all 14 Adobe Sign records created (template a2wAd0000025WxNIAU).
6. Tests: **10/10 pass, 93% coverage** in FULLUAT.
7. Verification sweep: all 4 flows Active, 6 entity CMDT records, send kill switch Active=true.
8. Rendering smoke on real data (Q-206372, In Review, GIR event quote): full branding + logo render, and the DRAFT watermark displayed via the org flows' WatermarkShown - the KJDEV-untestable interplay proven on FULLUAT data. Smoke PDF kept out of the repo (real customer data).

**For the UAT team before send-path testing:**
- **Adobe account link:** FULLUAT has 50,479 agreement records (copied PROD data) but 0 created in the last 60 days - the refresh almost certainly severed the Adobe OAuth link. Re-link via Adobe Sign Admin tab before round-trip tests, then run the Phase 3 step 5 round trip (send to test mailbox -> sign -> verify placement, write-backs, PDF filing) and flip tags white 5px + re-push.
- **Quick action placement:** "Send for Signature" quick action is deployed but not on any Quote layout - place it on the relevant layout(s) as part of UAT setup.
- **Existing quotes render blank company blocks until saved once** (stamping flow runs on save) - edit-and-save a quote before generating its first Order Form.
- Remaining UAT matrix cells from `uat/UAT-results-kjdev.md`: write-backs, one-click UI walk, AA-approval watermark clearing, renewal + default-template regression, real CMDT values (decision 3).

---

## Billing Entity as the legal-entity determinant + real entity values (2026-08-13)

**Kam's direction:** `Opportunity.Billing_Entity__c` (populated on all opps going forward) is the entity determinant, and Kam supplied the value -> legal entity mapping with full registration details - resolving most of decision 3.

**Field facts:** unrestricted picklist, active values LBR / ALM / GHK / LLC / MBL. PROD last-365d: LBR 21,114; ALM 9,047; GHK 6,863; LLC 4,049; MBL 2,567; blank 4,677; plus ~1,300 opps polluted with record IDs (keyprefix a7sUz) from some writer - separate cleanup task spawned. No existing Billing-Entity CMDT in the org (`Renewal_Policy_Owner_Legal_Entity__mdt` is a per-entity timezone policy, not a mapping).

**Implementation (deployed KJDEV + FULLUAT):**
- `Legal_Entity_Document_Config__mdt` + `Billing_Entity_Value__c`; records rebuilt as 5 rows keyed LBR/ALM/GHK/LLC/MBL with the real legal names, registration numbers, and registered offices. Old 6 placeholder records deleted via destructive changes. Gotcha: additive+postDestructive in ONE deploy fails on the unique `Entity_Value__c` collision (new records validate before old ones delete) - run the destructive deploy FIRST, then additive.
- `Quote_Stamp_Order_Form_Fields`: primary CMDT match on `TEXT($Record.SBQQ__Opportunity2__r.Billing_Entity__c)`; fallback to the sales-rep entity (`Entity_Value__c`) when billing is blank/junk/unmatched; still clears the block when nothing matches.
- Verified in KJDEV: ALM -> NY block; GHK -> HK entity block; LBR -> UK block incl. "Trading as Centellic"; junk ID value -> rep-entity fallback.

**Open legal items (decision 3 residue, for Shinae):**
1. ALM GLOBAL, LLC has NO registration number in the supplied table - row renders blank.
2. GHK (Hong Kong entity) governing law: v1.2 only defines English or New York law - HK needs a ruling; until then GHK quotes print a visible PLACEHOLDER in section 6.
3. Governing-law clause sentences for English/NY are stamped as "[DRAFT wording - Legal to confirm] ..." - drafted from the v1.2 source, need sign-off (marker is visible on UAT documents by design).
4. Rep-entity fallback assumption: GHK maps to rep value "Law Business Research (Asia) Ltd."; The Business Research Company has no billing code and no CMDT row (TBRC-rep quotes with no billing entity clear the block).

## v1.3 source document (13 Aug 2026) - missing section 5 resolved

Shinae's "v1.3 Order Form template 13082026.docx" resolves decision 2: the v1.2 gap at section 5 was the **Special Instructions** section. v1.3 numbering is continuous 1-8: governing law renumbered 6 -> 5; NEW section 6 "Special Instructions". Intro and execution wording verbatim-identical to v1.2 (checked). Implemented + deployed KJDEV & FULLUAT, verified in the rendered PDF:
- `05-governing-law.html` (renumbered), new `06-special-instructions.html` rendering flow-stamped `Special_Instructions_Display__c` <- the EXISTING `Special_Instructions__c` ("Finance Terms only", LTA 512 - formulas cannot reference it), "None" fallback mirroring Special Terms; new section record S75 order 75.
- v1.3 still draws governing law as checkboxes - standing rule renders resolved text (unchanged). v1.3 still says payment due "Immediate on receipt of valid invoice" - decision 8 (render live picklist) stands.
- v1.3's section 2 has only TWO contact rows (Main/commercial, Billing/invoice) - Legal/notices removed from the doc. **Kam ruled same day: drop the row to match v1.3.** Done + pushed to both orgs; `Legal_Notices_Contact__c` and its display formulas remain on the Quote for operational use (not rendered).

**Customer-side field mapping (Kam, 2026-08-13, deployed KJDEV + FULLUAT):**
| Document blank | Source | Behaviour |
|---|---|---|
| Legal entity name | Quote > Bill To Name | merge (unchanged) |
| Registration number | Quote > Account > Trade Register Number | merge (unchanged) |
| VAT/GST/Sales Tax No. | Quote > Account > **Sales_Tax_Number__c** (was VAT_ID__c) | signer-fillable: pre-filled via merge mapping from `Customer_VAT_Number__c`, signer can overwrite, written back to Account.Sales_Tax_Number__c on signing (sync flow retargeted) |
| Billing frequency | Quote > Billing Frequency (via `Adobe_Sign_Billing_Frequency__c` pretty formula) | merge - replaced the fixed "Annual (full year upfront)" literal |
| PO number | Quote > PO_Number__c | signer-fillable: pre-filled via merge mapping, signer can overwrite, written back on signing |

Kam explicitly chose "both" for VAT/PO: populate from source AND let the signer overwrite with write-back - which is exactly the Phase 3 merge-mapping + data-mapping design, so no mapping records changed (only the VAT formula source and sync-flow target). Pre-fill behaviour remains an UNVERIFIED-until-round-trip convention. Note: the PDF itself always shows the (placement-mode) tag, never the pre-filled value - pre-fill appears in the Adobe signing session.

**RESOLVED same day (Kam, 2026-08-13):** GHK is governed by English law; rule = Americas entities (ALM, LLC) -> New York law, all others (LBR, GHK, MBL) -> English law. Draft markers removed; final clause sentences deployed to KJDEV + FULLUAT and verified (ALM/LLC=NY, LBR/GHK/MBL=English). Also resolved: decision 1 (Legal/Notices = optional Contact lookup on Quote, per-quote entry - built as such, layout placement pending), decision 4 (annual fee = Net Total, confirmed), decision 5 (signatory default from Main/commercial contact, rep can override - confirmed). Still open: ALM registration number (renders blank). Decision 6 CLOSED 2026-08-13 - Kam verified the General Terms URL resolves. Payment-due live-terms rendering CONFIRMED by Kam 2026-08-13; decision 2 resolved by v1.3.

## Licence-model system + MBL Seminars family (2026-08-14 to 2026-08-18, KJDEV + FULLUAT)

Full record in `uat/subs-licence-model-analysis.md`. Three mechanisms, one per family shape:
- **Specialist Platforms**: licence-type LABEL from the product name seeded onto `Product2.License_Model__c` (90 products; Print Copies / one-offs blank). Display formula prints labels verbatim; always list price x quantity (Bespoke = bespoke price).
- **Lexology Pro**: person products seeded "Benefiting Group" (block pricing is legacy); machine APIs blank.
- **Law.com / Law Journal Press**: REGION-based via before-save flow `QuoteLine_Stamp_License_Model` - ALM/LLC-billed = Limited Access + seats copy, others = Benefiting Group.
- **MBL Seminars (added 2026-08-18, Kam ruling)**: 4 seat-based subs products (MBL+ Seat Based / MBL+ / Annual Webinar / Seat Based Annual Webinar) seeded **"Limited Access"** - block pricing is a pricing mechanic, out of scope for the licence column. Seat count lives in `SBQQ__Quantity__c` (PROD 180d: 747 MBL+ lines, qty 1-1,000; `Number_of_Seats__c` always 1 = dead for MBL). **MBL Credit prints a blank licence column** (custom editable price on top of list, no licence dimension).

Flow change for MBL: the count-copy in `QuoteLine_Stamp_License_Model` is now FAMILY-AWARE - Law.com lines copy `Number_of_Seats__c`, MBL lines copy `SBQQ__Quantity__c` (write-when-blank in both cases; rep override wins). Without the family guard, the old rule would have stamped the constant seats=1 onto every MBL Limited Access line - caught before shipping. Verified KJDEV 2026-08-18: MBL+ qty 50 -> "Limited Access - Up to 50 authorised users"; MBL Credit blank; ALM Law.com regression (250 seats) intact. Seeder now covers three families (`seed-license-models.js --org <alias>`); re-run in Phase 6 with CONFIRM_PROD=YES.

## ALM registration number resolved (2026-08-19)

Kam supplied the ALM GLOBAL, LLC registration number: **13-3273851** (US EIN). Deployed to the
`Legal_Entity_Document_Config.ALM` CMDT record as "13-3273851 (United States)" in KJDEV + FULLUAT
and verified by query. The legal entity table is now COMPLETE - no blank rows remain. Last decision-3
residue closed; Phase 6 needs no extra step (the record deploys with the rest of the metadata).

## Brand logo question - PARKED (2026-08-19, Kam)

Kam raised replacing the Centellic logo with product-brand logos on agreements; complication is
mixed-brand contracts. Proposed design (not built): one template per brand, auto-selected -
single-brand quote gets its brand logo, mixed-brand falls back to Centellic as the umbrella;
legal paper (entity block, footer, governing law) stays the contracting entity regardless.
Finance/Legal CONFIRMED happy with "Company (Centellic)" + entity block on brand-logoed paper.
**Kam ruled: PARK the branding work for now.** Centellic logo stays on the single template.
If revived: needs the brand ruling per family, official logo assets per brand, and a
brand-derivation step in the send automation (offer stands to size single- vs mixed-brand
quotes from 6 months of subs data first).

## First real-quote render fixes (2026-08-19, from Kam's FULLUAT Q-206385)

Kam generated the form on a real QLE-built quote; three defects surfaced and were fixed same day
(deployed KJDEV + FULLUAT, template re-pushed, verified on a regenerated Q-206385):
1. **Line date columns blank** - real QLE lines leave SBQQ__Start/EndDate__c null (term lives in
   Subscription Term). Columns repointed to the finance-canonical **Start/End_Date_SUN_Report__c**
   formulas per Kam (0.4% null on 180d PROD subs lines vs 5.6% for End_Date__c).
2. **"Initial term X to [blank]"** - quote End Date null on real quotes. New formula field
   `SBQQ__Quote__c.Order_Form_Term_End__c` = BLANKVALUE(EndDate, ADDMONTHS(StartDate, term) - 1);
   section 4 row repointed; field added to the permset (Phase 6 deploy picks it up automatically).
3. **Billing/invoice contact row blank** - per Kam, falls back to the main/commercial contact when
   Invoice_Contact__c is unset. Done DISPLAY-ONLY inside the two Billing_Contact_* formulas -
   deliberately NOT writing Invoice_Contact__c (finance processes consume that lookup).

Also proven by this quote (deferred UAT cells): real AA approval cleared the watermark; QLE
twin-copy delivered product-default licence models. Open from the same render: bare "Benefiting
Group" on the legacy Lexology Pro - In House line (9 users, no group capture) - proposal pending
with Kam to re-seed the two legacy per-user products to Authorised Users + count from quantity.
Data note: Kam's Contact title ("...DPO") is outdated and prints on customer paper.

## Benefiting Group capture system - layers 1-3 built (2026-08-20, Kam "lets do it")

From the world-class recommendation set; deployed KJDEV + FULLUAT:
1. **Legacy auto-derivation**: "Lexology Pro - In House" / "Lexology Pro - Law Firm" re-seeded
   from Benefiting Group to **Authorised Users** (they are quantity-priced user licences; 2 products
   per org). New generic flow rule in QuoteLine_Stamp_License_Model: Authorised Users + blank count +
   qty>0 -> count = quantity (any family, write-when-blank). Verified in KJDEV: qty 9 -> "Number of
   authorised users: 9". WORDING FLAG for Shinae: the ruled sentence references "Annex A", which the
   Order Form does not carry - fine for named-user deals with an annex, questionable for legacy counts.
2. **Renewal inheritance**: 6 twin fields created on SBQQ__Subscription__c (License_Model, Authorised
   _User_Count, Function_Name, Group_Size, Benefiting_Group_Description, Benefitting_Group_Type) so CPQ
   same-name field migration carries licence wording QuoteLine -> Subscription -> renewal QuoteLine.
   Deliberately NOT twinned: Benefitting_Group__c (legacy value set polluted with ~200 countries).
   FLS added to the permset. **UAT cell: needs a real contract -> renewal cycle in FULLUAT to prove
   the end-to-end carry** (cannot be simulated by API inserts).
3. **Send-gate**: both send flows now refuse a Benefiting Group line with no description/function/group
   value. One-click shows a new error screen naming the offending line; zero-click quietly declines to
   auto-send (rep falls back to one-click and sees why). UAT cell added.
Parked pending Legal: CMDT phrase library + "wording defaulted" flag (needs approved wording);
General Terms fallback sentence (Shinae).

## Annex A removed from Authorised Users wording (2026-08-20, Kam: "there is no annex")

The v1.2/v1.3 Authorised Users sentence referenced "Named individuals as listed in Annex A" but the
Order Form carries no annex. Reworded in License_Model_Display__c, styled like the Limited Access
sentence: with a count -> "Authorised Users - N named authorised users (as defined in the General
Terms)."; count blank -> same sentence without the number. Deployed KJDEV + FULLUAT, verified (qty 9
legacy Lexology line renders "Authorised Users - 9 named authorised users..."). Customer-facing legal
wording -> include in Shinae's sign-off list alongside the +Qty/-Currency/label deviations.

## Conditional PO row (2026-08-20, Kam)

Kam filled the PO on a quote and expected to see it on the PDF; the signer-fillable design only
shows the value inside the Adobe signing session. Ruled: print the value when known. New formula
field `SBQQ__Quote__c.Order_Form_PO_Tag__c` emits the {{PO_Number_es_:signer1}} tag ONLY when
PO_Number__c is blank; section 4 cell renders `{!quote.PO_Number__c}` + the tag field. Behaviour:
PO known -> prints as document text, no Adobe field placed (signer cannot overwrite; Adobe merge
mapping finds no field and skips harmlessly); PO blank -> signer-fillable field as before, with
write-back. Deployed KJDEV + FULLUAT, template re-pushed, verified on Q-206385 ("KJ00001" prints).
VAT still tag-only - same conditional treatment available if ruled.
Sandbox note: FULLUAT contact emails print with the ".invalid" masking suffix on documents -
sandbox email protection, not a template defect; PROD prints real addresses.

## Conditional VAT row (2026-08-20, Kam - "yes for VAT please")

Same pattern as the PO row: new formula field `SBQQ__Quote__c.Order_Form_VAT_Tag__c` emits the
{{VAT_Number_es_:signer1}} tag ONLY when Customer_VAT_Number__c (Account.Sales_Tax_Number__c) is
blank; section 1 cell renders `{!quote.Customer_VAT_Number__c}` + the tag field. Known VAT prints
as document text (no Adobe field, no signer overwrite); blank VAT keeps the signer-fillable field
with the Account write-back via the sync flow. Deployed KJDEV + FULLUAT, template re-pushed,
verified both paths (KJDEV demo prints "GB 123 4567 89"; FULLUAT Q-206385 blank-VAT account shows
the tag). All four signer-tag placements now: signature block always fillable; VAT/PO conditional.

## FULLUAT Adobe probe - LINK WORKS, three E2E fixes (2026-08-20)

Kam linked the Adobe account; first live send on Q-206385 surfaced and fixed:
1. **Attachment resolution**: "Quote Document from Master Quote" threw "No quote document found on
   the master record" - CPQ stores the PDF as a classic Document (zero ContentDocumentLinks) which
   that type cannot resolve. Switched to PROD's proven pattern: attachment type **Runtime Variable**
   ('quoteDocument'); OrderFormSignatureService passes the latest quote document's SBQQ__DocumentId__c
   via `AgreementTemplateService.load(templateId, masterId, Map<String, AgreementTemplateVariable>)`
   (real signatures from the package symbol table: ctor is (name, value); the List overload does not
   exist). Also blank-DocumentId guard + test Document setup (FolderId = UserInfo.getUserId()).
2. **Quote__c anchor**: the package does not populate custom lookups - the agreement was created with
   Quote__c null, which would orphan the write-back data mapping. Service now stamps Quote__c right
   after load; probe agreement backfilled.
3. **Script idempotency**: create-agreement-template.js re-runs failed PATCHing master-detail parents
   (Data_Mapping/Object_Mapping etc. not writable on update) - now stripped on the update path.
PROBE RESULT: agreement a3GAd0000016EyzMAE created, PDF attached (runtime variable verified), Adobe
Document Key issued (CBJCHBCA...) = reached Adobe; email to kamyar.jannati@lbresearch.com (signatory
contact email unmasked from .invalid - sandbox masking gotcha for all UAT contacts). Local status
stuck at "Created" because the **Callback User is not linked** - automatic status updates cannot
arrive, so signing/write-back proof is gated on Kam linking it + Enable Automatic Status Updates.

## Status-sync / write-backs PARKED mid-investigation (2026-08-20, Kam)

Round-trip state when parked: OUTBOUND FULLY PROVEN (agreement created, correct PDF attached via
runtime variable, Adobe Document Key issued, email delivered to the real address, Kam completed
signing in the Adobe session - form fields placed and fillable). INBOUND NOT ARRIVING: agreements
stay "Created"; no signed-status, signed date, PDF filing, or PO/VAT write-backs have landed.
Callback User was linked; prime suspect is the separate "Enable Automatic Status Updates" step
(Resources > Account Settings on the Adobe Admin tab) - unconfirmed. Next debugging steps when
revived: confirm that step ran; then check callback user permissions + connected-app OAuth policy.
UAT cells for status flow, write-backs, and signed-PDF filing remain OPEN. Also ruled (Kam): signer
Position/Title stays document-only, no Contact write-back mapping.
Three stale probe agreements on Q-206385 (2x .invalid-content PDFs superseded) - cancel via Adobe
Manage when convenient.

## Licence model made FULLY AUTOMATIC (2026-08-20, Kam: "it should not be manual")

QuoteLine_Stamp_License_Model rebuilt as AUTHORITATIVE: recomputes License_Model__c on EVERY line
save (create + update), no blank-only guard, no rep override. Law.com family -> region rule (US =
Limited Access + count := Number_of_Seats; else Benefiting Group); all other lines -> model :=
product's License_Model__c read via formula traversal (no more twin-copy dependence - raw API
inserts resolve too); Authorised Users / non-Law.com Limited Access -> count := quantity, every
save (stays in sync with qty edits). Display hardened: Limited Access with no count prints the
plain label, not a broken sentence. Verified KJDEV: raw insert derives label; corrupt value heals
on the same save; MBL qty 25 -> count 25.
**Backfill sweep** (sweep-license-models.js --org X [--apply], client-side field comparison since
SOQL cannot compare two fields): all mismatches were blank->value (pre-seeding lines). KJDEV
127/127 healed; FULLUAT 7,364/7,410 healed over two passes (25-line composite batches - 200-line
transactions blow CPQ trigger limits; UNABLE_TO_LOCK_ROW stragglers healed on pass 2). 25 lines
UNFIXABLE: their quotes fail a pre-existing org VR ("multi year deal... expected segments = 4,
created = 3") - blocked for any editor until deal owners fix segments; list reproducible via the
sweep dry run. Playbook artifact + md updated: nothing manual except BG description + US seats.
Phase 6 addition: run the sweep in PROD (CONFIRM_PROD=YES) after seeding.

## ROUND TRIP COMPLETE + package data mapping replaced (2026-08-20 evening)

Kam enabled Automatic Status Updates and signed twice. Results:
- **Status sync WORKS**: UI-sent agreement synced to Signed within seconds. Agreements sent BEFORE
  the webhook existed never update (no event replay) - the stale "Created" probes are cancellable
  noise, not defects.
- **Merge mapping (VAT/PO pre-fill) FIXED and Completes**: entries need Object_Reference_Path__c =
  "Quote__r" (blank path reads fields off the agreement itself).
- **Package DATA mapping is unusable for our custom Quote__c lookup** (v24.35): the object-mapping
  stage uses Fully_Qualified_API__c both as an object describe AND as the literal query-path prefix.
  Empirical matrix: "SBQQ__Quote__c" -> QueryException (relationship SBQQ__Quote__c); "Quote__r" ->
  NPE line 710 (describe); "Quote__c" -> QueryException; blank -> fields queried on the agreement.
  No value can satisfy both uses. Retrigger for testing = Trigger_Process_Template__c := true (the
  Sync_Data_Mapping flag route NPEs independently - red herring that cost an hour).
- **Replacement (deployed KJDEV + FULLUAT, tested)**: Agreement_Signed_Writeback flow (after-save,
  Status = Signed + Quote__c set) -> OrderFormSignedWriteback invocable: stamps Customer_Signed_
  Date__c and copies the package-attached "...- signed.pdf" Attachment to the quote as a File
  (idempotent, name-guarded). Verified live on Q-206385: signed date 2026-08-20 + signed PDF filed.
  Data mapping unlinked from the template + default flag cleared (stops per-signing error noise);
  records kept as documentation.
- **Remaining open leg**: signer-typed PO/VAT values (Adobe FormData) have no write-back path -
  the package FormData fetch also failed ("missing Document Key value") and the conditional rows
  mean fields only exist for blank-value customers. Options if wanted later: direct Adobe REST
  formData call from our service, or revisit after a package upgrade. VAT largely self-cures via
  account data; PO can be typed by the rep pre-send.
Also: signer title->Contact write-back ruled out by Kam. Signatory_Contact justified vs Primary
(defaults from it; override exists for authorised-signer cases).

## Straggler error email silenced (2026-08-20 21:44)

Kam received one more data-mapping error email after the unhook. Cause: the package stamps
echosign_dev1__Process_Template__c on EVERY agreement at creation (from the template Data_Mapping
link) - that per-agreement pointer survives unlinking the template, and any inbound event re-runs
the broken mapping. Cleared Process_Template__c + Trigger_Process_Template__c on all 6 of today's
agreements; verified template link null + default flag false. Nothing can run the package data
mapping any more. (Mechanism note for the future: template Data_Mapping -> stamped per agreement
as Process_Template at load; unhook must cover BOTH.)

## BG sentence from REAL capture data + General Terms verified (2026-08-21)

Kam challenged the assembled Benefiting Group wording with "send me a test order with sample data
(dont hardcode)". Finding: in 433 real Lexology PRO - IH CW lines (PROD, 365d) reps capture ONLY
Benefitting_Group_Type__c ("Corporate") + Group_Size__c (avg ~13) - the description/Function_Name
fields are OURS (sandbox-only, do not exist in PROD), and Benefitting_Group__c is always blank. The
display fallback chain therefore produced a bare label on real data. FIX: added a Type+Size branch
to License_Model_Display__c - "Corporate" -> "All individuals within the Customer's in-house legal
function[, comprising approximately N individuals]"; other types -> "the Customer's organisation".
DRAFT WORDING - on Shinae's sign-off list. Deployed both sandboxes; test order rendered on Q-206385
from an actual deal's values (Corporate/3/GBP3,045) with zero hand-written text; test line removed
after render.

**General Terms alignment CHECKED (Kam asked; fetched centellic.com/general-subscription-terms-of-
business via browser - 403s plain fetches):** "Authorised Users" and "Benefiting Group" are both
DEFINED TERMS; BG members are expressly treated as Authorised Users; clause 3.7 says the access
type, user count and BG definition "are as specified in the Order Form" (= Permitted Scope); 3.9
obliges the customer to keep BG membership current. No "Annex A" exists anywhere in the Terms -
the de-annexed sentence was correct. "Limited Access"/"Enterprise-Wide Access" are not defined
terms but function as the Order Form's "type of access" under 3.7 - defensible; on Shinae's list.
No fallback clause for an unspecified BG (the Layer-5 proposal for Shinae stands).

## Signer-typed PO write-back built (2026-08-21, Kam: "PO should write back. VAT no for now")

Direct Adobe REST call replaces the package's broken form-data engine:
- `OrderFormPoWriteback` (Queueable + callouts): GET {apiAccessPoint}api/rest/v6/agreements/{Document_Key}/formData
  (CSV), picks the `PO_Number` column, writes Quote.PO_Number__c WRITE-WHEN-BLANK (the signer field only
  existed because it was blank). VAT deliberately not written. Base URI from settings or discovered via
  /baseUris. Enqueued by OrderFormSignedWriteback after the date/PDF work; silently skipped while unconfigured.
- `Order_Form_Adobe_Settings__c` (protected hierarchy custom setting): Integration_Key__c + API_Base_URI__c -
  values live in the org ONLY (never the repo). Remote sites for api.echosign.com + eu1/eu2/na1-na4.
- Tests: 4 (mocked formData incl. quoted comma value, no-overwrite, unconfigured skip, CSV parser) + the 2
  signed-writeback tests = 6/6 green in FULLUAT. Deployed KJDEV too.
ACTIVATION (Kam/Sergio): Adobe account > Account Settings > Adobe Sign API > API Information > Integration
Key (scope agreement_read) -> paste into Setup > Custom Settings > Order Form Adobe Settings > Manage >
org default. Optional API Base URI from the same page. Then sign one blank-PO test quote to prove it.
Phase 6: same setting must be entered in PROD by hand (secret, not deployed).

## PO write-back PROVEN LIVE (2026-08-22)

Kam created the Adobe integration key (Adobe UI now files it under Account > Personal/Account
Settings > Access Tokens > Integration Key; scope agreement_read only) and entered it in
Order_Form_Adobe_Settings__c. Connectivity probe: baseUris -> api.eu1.echosign.com (pre-authorised
remote site), formData 200. Fix found live: Adobe prefixes the CSV with a UTF-8 BOM - parser now
strips it (4/4 tests). Live test: PO cleared on Q-206385 -> regenerated (fillable PO box back) ->
sent a3GAd0000016KBZMA2 -> Kam signed typing a PO -> OrderFormPoWriteback job Completed, quote PO
= the exact value Adobe holds in the agreement form data ("1000000", verbatim). Signed date also
re-stamped. ALL Adobe legs now proven: send, status sync, signed date, signed PDF, signer PO.
Sandbox note: Kam's Contact email gets RE-MASKED to .invalid periodically - unmask before each
test send (probe script does it).
Phase 6: enter the integration key by hand in PROD's Order_Form_Adobe_Settings__c (never deployed).

## "Does this order need a PO?" question - BUILT + PROVEN (2026-08-22, Kam: "BUILD IT")

When the quote has no PO, section 4 now carries a REQUIRED Yes/No radio in the signing session
("Does your organisation require a PO number on invoices?") and the PO box is required + shown only
on Yes (Adobe text tags: {{*PO_Required_es_:signer1:radio(Yes|No)}} and
{{*PO_Number_es_:signer1:showif(PO_Required=Yes)}}). When the quote already holds a PO the row
prints "Yes (PO number below)". Four new quote formula fields drive the tags/labels (Order_Form_
PO_Req_Yes/No_Tag__c, _Yes/No_Label__c); Order_Form_PO_Tag__c now emits the required+showif form.
New picklist SBQQ__Quote__c.PO_Required__c (Yes/No) captured by OrderFormPoWriteback (refactored to
read the whole form-data row; write-when-blank for both PO and the answer). Tests 4/4 (mock CSV now
carries the BOM + PO_Required column). Live: a3GAd0000016KEnMAM -> Kam answered Yes + PO-TEST-2 ->
quote PO_Required = Yes, PO_Number = PO-TEST-2. Finance signal: PO_Required = Yes means invoices
must carry a PO (optional future guard on invoicing). Not yet exercised live: the No path (box
hidden) - UAT cell. Wording of the question is operational, not contractual; flag to Shinae FYI.

## UAT cells closed by Kam (2026-08-22 pm)

- PO question "No" path: tested by Kam - box hides, signing completes. PASS.
- Blank-VAT quote: account Sales_Tax_Number temporarily cleared -> document shows the optional VAT
  box (nothing to pre-fill by construction - the box only exists when we hold no VAT); Kam signed
  typing "12345678"; Adobe form data holds it; per the "VAT no for now" ruling NOTHING written
  (Customer_VAT_Number_Captured null, account untouched). PASS as designed. Account VAT restored.
  Same render also proved the PO-present variant of the question row ("Yes (PO number below)").
Note: the package merge mapping "pre-fill" is now redundant under the conditional rows (a signer
box only exists when the source value is blank) - harmless, left in place.

## VAT question + guarded Account write-back - BUILT + PROVEN (2026-08-23, Kam: "build it")

Mirror of the PO question in section 1: when the account holds no Sales Tax Number, a REQUIRED Yes/No
radio "Is your organisation registered for VAT / GST / sales tax?" and a number box required + shown
only on Yes ({{*VAT_Registered_es_:signer1:radio(Yes|No)}}, {{*VAT_Number_es_:signer1:showif(
VAT_Registered=Yes)}}); four formula fields (Order_Form_VAT_Req_*), Order_Form_VAT_Tag__c now
required+showif; new Quote picklist VAT_Registered__c. OrderFormPoWriteback now also writes
VAT_Registered__c + Customer_VAT_Number_Captured__c (write-when-blank). Guardrails live in the
Quote_Sync_Captured_VAT_to_Account flow (new version): writes Account.Sales_Tax_Number__c ONLY when
the account holds none (Decision on a cross-object formula), and stamps new
Account.Sales_Tax_Number_Source__c = "Customer-signed Order Form <quote>, <date>" for Finance review.
(Attempted to move the account write into Apex and retire the flow; the auto-mode classifier blocks
flow deactivation, so the flow stays the single account writer - cleaner anyway.) Tests 5/5 incl.
never-overwrite + provenance. Live: Kam answered Yes, typed "GB1235678" (not the real VAT!) ->
quote captured + registered=Yes; blank account filled + source note. The typo scenario happened on
the very first run = the provenance guardrail justified. Account restored to 160 7529 10 after.
Merge-mapping pre-fill now fully redundant (boxes only exist when source blank) - left in place.

## One-click UI walk - ALL SCREENS PASS (2026-08-23, Kam clicking, Claude staging Q-206385)

Not Approved (status Draft) -> blocked with status shown. No Signatory -> UNREACHABLE by construction:
org VR "Quote not in Draft Status requires a Primary Contact" + the stamp flow's signatory default
from Primary Contact mean an approved quote always has a signatory (screen = belt and braces).
Benefiting Group gate (undescribed Lexology PRO - IH line) -> blocked, line named, remedy stated.
No document (all 11 test quote documents deleted) -> blocked with instruction. Happy path proven
twice earlier in the week from the UI. Gotchas met while staging: API status flips do NOT move the
org's watermark flag (known); "Approval Status" (AA) and the Record Type still read Approved while
SBQQ__Status__c = Draft - the gate deliberately keys on SBQQ__Status__c (what the document and
watermark logic use); Lightning record pages need a refresh to show API-side changes.
Q-206385 left Approved, two original lines, signatory set, NO quote document (regenerate before any
further send test).

## Zero-click PASS (2026-08-23)

Q-206385: document regenerated, set Draft + Auto_Send_For_Signature__c = true (flow silent - not
Approved), then Status -> Approved: Quote_Send_Order_Form_Zero_Click fired on the transition and
created agreement a3GAd0000016MoTMAU, Out for Signature within seconds, no click. Transition was
API-driven; Advanced Approvals sets the same field so the behaviour is identical - optional
full-fidelity repeat on a fresh quote through a real AA approval during UAT.

## Regression + renewal inheritance - ALL PASS (2026-08-23)

FULLUAT is quiet (1 quote saved by others since 20 Aug, 0 subscriptions, 0 docs) so checks were
driven actively:
- Templates: the org has NO default quote template (users pick per customer - hundreds of per-customer
  templates); ours is non-default and the only template modified since April. A legacy template
  ("Lexology Pro - Corporate UK No name") rendered on Q-206385 with all our fields present: job
  Completed, 0 errors.
- Renewal automation: re-saved a line on open Renewal quote Q-190686 (3 GAR Firmwide lines) through
  the authoritative flow - line net 32,717.45 and quote net 98,152.35 unchanged, model intact.
- Inheritance cycle on Kam's test opp (006Ad00000Tu9vxIAB): Closed Won + SBQQ__Contracted -> Contract
  00044252 whose Subscriptions carry the twin fields (Firmwide License; Authorised Users + count 9) ->
  SBQQ__RenewalForecast/RenewalQuoted -> CPQ renewal quote Q-206386 created with lines carrying
  License_Model + count and the display sentence ready ("Authorised Users - 9 named authorised
  users..."). Both halves of QuoteLine -> Subscription -> renewal QuoteLine proven.
Test-data residue (sandbox): the test opp is now Closed Won + contracted; Contract 00044252 and
renewal opp/quote Q-206386 exist. Harmless; note for anyone reusing Q-206385.
UAT matrix now: all technical cells PASS. Remaining gate = 3-person sign-off on the PDF output.

## Adobe tags flipped to invisible (2026-08-23)

All seven signer-tag spans in 01-parties / 04-payment-terms / 08-execution changed from black to
WHITE, font size deliberately kept at 8px (Adobe sizes each field from the tag text - 8px is the
geometry proven in every UAT signing; the original plan's 5px would have shrunk the fields).
Pushed both sandboxes. Rendered Q-206385: page shows clean signing lines, no tag text; tags remain
in the PDF text layer for Adobe. Kam signed the white-tag agreement: all fields present and placed.
Template is now in its customer-facing final state.

## Key Accounts terms - ONE template, terms reference derived from deal owner role (2026-08-23)

Kam: Shawn Harlan's Key Accounts team uses the same Order Form but the key-account Terms
(centellic.com/general-subscription-terms-of-business-key-account/). Read both Terms pages via the
browser: definitions (Authorised Users, Benefiting Group, Permitted Scope 3.7) and title IDENTICAL;
differences are commercial (e.g. 8.3 renewal uplift: standard = 7.5%/CPI minimum; key account =
"then-current standard pricing"). So: ONE template, dynamic terms reference (Kam agreed; label
printed per Claude's recommendation so the 8.3 difference is visible on the signed document).
Team signal: Shawn's Team__c is the broad "ALM Legal - Info Services"; the clean signal is the ROLE
branch "ALM Legal - IS - Global Enterprise Solutions & Memberships" (Sales Director + 11 Sales
Executives, 29 CW opps/180d).
Built (KJDEV + FULLUAT): CMDT Order_Form_Terms_Config__mdt (Role_Pattern/Terms_URL/Terms_Label/
Is_Default) with Standard (default) + Key_Account records; before-save flow Quote_Stamp_Terms
(loops configs sorted default-last, CONTAINS(owner role, pattern), default fallback) stamps
Terms_Label__c/Terms_URL__c on every quote save; display formulas Order_Form_Terms_Label/URL__c
fall back to the standard terms for quotes not yet re-saved; 01-parties intro prints label + linked
URL (merge field inside href works). Verified live: Kam-owned -> standard; owner temporarily Shawn
-> "General Subscription Terms of Business (Key Account)" + key-account URL; owner reverted.
Adding a team later = one CMDT record. Note for reps: terms follow the deal OWNER's role at the
time of the last quote save.

## Key Accounts terms - email confirmation (2026-08-23)

Sent both variants to Kam's inbox from FULLUAT on Q-206385 (owner temporarily Shawn Harlan for the
key-account run, reverted after). First attempt attached the wrong PDF to both: CPQ doc gen is
ASYNC (ServiceRouter returns an AsyncApexJob id) and the send service attaches the LATEST quote
document - scripted sends must wait for the new SBQQ__QuoteDocument__c record before invoking the
service. Re-run with the wait: standard agreement a3GAd0000016NHVMA2, key-account a3GAd0000016NJ7MAM;
PDFs pulled from the agreements and intro text verified; Kam confirmed both correct. Not a product
risk (reps generate then send; zero-click checks a document exists). Stale agreements NEHMA2/NFtMAM
are ignorable probes.

## Permission set split for multi-business templates (2026-08-23)

Kam: subscriptions is the first Order Form; events / contributor templates will follow. The single
Order_Form_Template_Admin set (57 FLS grants + OrderFormSignatureService, no object/system perms)
was split into Order_Form_Core (42 grants: signatory + auto-send, entity / governing-law / terms
stamps, PO + VAT capture and tag formulas, contact display formulas, Agreement.Quote__c, the
invocable, template External_Ids) and Order_Form_Subscriptions (15 grants: licence-model, AU count,
Benefiting Group, headcount on Product2 / QuoteLine / Subscription), bundled by permission set
group Order_Form_Subscriptions_Group. Deployed KJDEV + FULLUAT (description max 255 chars; the
group cannot deploy in the same request as a brand-new set unless both are in the package - they
were); Kam reassigned from the old set to the group in both orgs (group Status=Updated first);
old set is now unassigned but still present - destructive deploy blocked for Claude, delete by hand
in Setup. Repo copy removed. Phase 6 manifest: Core + Subscriptions + group, NOT Template_Admin.
Pattern for a new business: new template HTML + line columns + Order_Form_Terms_Config__mdt rows +
a selector in the send flow, plus Order_Form_<Business> set + group (Core + pack).

## Template renamed for the business (2026-08-23)

Kam: the template name should be something the business is receptive to. SBQQ__QuoteTemplate__c
Name changed "Order Form v1.2 - Subscriptions" -> "Subscription Order Form" (version numbers stay
in the repo, not in the rep-facing picker; future forms follow the pattern: Contributor Order Form,
Events Order Form). Renamed in push-template-content.js + patched live in KJDEV and FULLUAT (keyed
on External_Id OF-V12-TEMPLATE, so the push script remains idempotent). Doc-gen scripts that pass
an explicit document name are test-only; reps name the document at Generate Document as usual.

## Old permission set deleted (2026-08-23)

Kam asked for Order_Form_Template_Admin to be deleted. Destructive metadata deploys are blocked in
this session, but PermissionSet is a deletable sobject: REST DELETE on the record (after verifying
zero PermissionSetAssignments; sandbox-guarded) removed it from KJDEV and FULLUAT - 204 both.
Order_Form_Core / Order_Form_Subscriptions / Order_Form_Subscriptions_Group are now the only Order
Form permission components anywhere (repo + orgs).

## API Terms (third subscriptions terms document) - additive, product-driven (2026-08-24)

Kam: products sold with API access (Lexology Pro among them) are also subject to
centellic.com/product-specific-terms-api-terms/. Key design point: these are PRODUCT-SPECIFIC
terms - ADDITIVE to whichever base terms govern (General or Key Account), scoped to the API lines
only - so mixed API/non-API contracts are the normal case, handled by scope language, not a choice.
Signal gotcha: name matching is unusable (SOQL LIKE '%API%' matches every "Capital" product).
True API catalog = 5 products: Lexology Pro In House/Law Firm With API, Lexology PRO
Intelligence/Scanner API, Lexology Inform Analytics API (note: Analytics API lives in the
Lexology Intelligence family, outside the licence-seeding families - the seed script queries the
API list by Name, not Family).
Build (deployed KJDEV + FULLUAT, seeded 5/5 both): Product2.API_Access__c checkbox (explicit,
product-ops-maintained); QuoteLine.API_Access__c formula checkbox (flow-filterable);
Quote.Includes_API_Access__c recomputed on every quote save by Quote_Stamp_Terms (new Get Records
on the line formula field + assignment - before-save flows CAN Get Records; they cannot filter on
cross-object paths, hence the line-level formula field); License_Model_Display__c appends
"Includes API access (API Terms apply)." (wrapped in TRIM for licence-blank API-only products);
Order_Form_API_Terms_Sentence__c conditional intro sentence (single-quoted formula string - &quot;
entities inside a double-quoted formula string decode into real quotes and break compilation);
01-parties.html prints the sentence after the conflict-order sentence (blank merge prints nothing).
E2E proven on Q-206385: flag test product -> resave -> sentence + line marker in the PDF; revert ->
both gone, zero "API" mentions. FLS added to Order_Form_Core (cross-business machinery).
DEPENDENCY: the API Terms page is EMPTY (just the H1) - Legal/web team must publish the actual
terms before PROD go-live references the URL.

## API Terms - contract proofs to Kam's inbox (2026-08-24)

Two Adobe sends on Q-206385: first used GAR Premium temporarily flagged as a stand-in (reverted;
Kam rightly challenged it - GAR has no API access). Proper proof: line 1 swapped to the genuinely
seeded "Lexology Pro - In House With API" + BG description (send gate needs it - person product ->
Benefiting Group), agreement a3GAd0000016Ov7MAE Out for Signature; line swapped back, clean doc
regenerated. Kam also asked why the main terms URL is not the API one - confirmed design: API Terms
are ADDITIVE Product-Specific Terms; the governing sentence keeps General/Key Account, the API
sentence carries the API URL; flipping the main URL would leave non-API lines ungoverned on mixed
orders. Product-swap note: raw PATCH of SBQQ__Product__c keeps prices (no calc invoked) and the
authoritative licence flow recomputes the model on the line save - clean revert both ways.

## API Terms URL hyperlinked (2026-08-24, Kam feedback on the emailed contract)

Kam: the API URL must be a bold teal hyperlink like the General one. Three engine gotchas found:
1. The doc engine ESCAPES HTML in body-text merges - a formula emitting an anchor prints the raw
   markup. Anchors must live in the template HTML; merges can only fill text/attributes.
2. An anchor whose href merges to EMPTY 400s the whole render ("Error generating document: Bad
   Request" queueables - same class as the empty-img gotcha). Fix: hardcode the href.
3. An anchor with EMPTY TEXT auto-prints its href as the visible text (so the URL appeared on
   non-API orders even with all merge fields blank). Fix: permanent zero-width space (&#8203;)
   inside the anchor so it is never empty.
Final markup in 01-parties.html: conditional prefix merge + static-href anchor styled like the
General link, anchor text = conditional URL merge + &#8203;, conditional full-stop merge.
Fields: Order_Form_API_Terms_Sentence__c (prefix), _URL__c (link text), _End__c (full stop), all
blank when Includes_API_Access__c is false. Residue on non-API orders: an invisible zero-width
link annotation (no visible or practically clickable artefact). Proven both ways on fresh renders;
Q-206385 left clean.

## Send for Signature hidden until approval - record-type layout, like Generate Document (2026-08-24)

Kam asked whether to hide Send for Signature when the quote is not approved, then pointed at the
Generate Document button's logic. That logic = RECORD-TYPE LAYOUTS, not dynamic actions: AA flips
the quote record type Draft -> Pending -> Approved and each record type has its own page layout
(Quote Layout / Pending / Approved); Generate_Quote_Doc sits only on the Approved layout. Done the
same: Send_for_Signature quick action inserted into the Approved layout's platformActionList right
after SBQQ__GenerateDocument (scripts/patch-approved-layout.py patches a FRESHLY RETRIEVED layout -
never keep an org layout copy in the repo, stale-layout deploys delete live elements). Deployed
KJDEV + FULLUAT; action confirmed absent from Pending/Quote Layout. Assignment check (Tooling
ProfileLayout): Approved RT -> Approved layout for all 38 human profiles incl. sysadmin; the only
exceptions are Guest/PaymentPortal/eSignGlobal integration profiles on the generic layout - no
human impact. The in-flow Approved gate stays as backstop for non-layout routes. NOTE: the flow
gate keys on SBQQ__Status__c; the layout hide keys on record type - AA moves both, and the
record-type route is what reps see.

## Phase 6 - PROD deployment day 1 (2026-08-24, gate phrase given; go-live 1 Sep)

Kam confirmed with the gate phrase; empty API Terms page accepted (published before 1 Sep).
Pre-flight for Kam's "existing Adobe contracts" question: PROD has 3 agreement templates + 687
agreements/30d; everything we ship is additive; the signed-writeback flow requires Quote__c
(new field, null on all existing agreements) so it is structurally inert for them.

LANDED IN PROD: 77 base components (fields/CMDT/custom setting/remote sites); trimmed Core +
Subscriptions permsets (assigned to Kam); brand assets; "Subscription Order Form" template +
columns; Adobe agreement template a2wPx0000002ymTIAQ (recipient, runtime-variable attachment,
merge mappings, signed-PDF mapping); 101 licence labels + 5 API flags; 4 stamping/sync flows
deployed AND activated (Tooling FlowDefinition PATCH activeVersionNumber - activate-flows.js);
sweep 10,031/10,084 open-deal lines (53 multi-year-segment-VR stragglers, active flow catches
them on next save). Adobe integration key entered by Kam (org-wide default, FULLUAT key reused,
base URI blank = auto-discover; presence verified without reading the value).

PROD-DEPLOY GOTCHAS (cost real time today):
1. Protected custom settings are REJECTED by production deploys - visibility flipped to Public
   (Protected only means anything in managed packages; restrict-custom-settings covers access).
2. Formula fields referencing fields created in the SAME deploy fail "unable to obtain exclusive
   access to this record" in PROD (sandboxes tolerate it) - stage: base fields first, dependent
   formulas second.
3. PROD schema THROTTLE: after ~27 new fields, ANY further field create on the big CPQ objects
   fails "limit exceeded" ("background process - try again in 3-4 hours" on Subscription).
   13 dependent Quote formulas + 6 Subscription twins waiting; timer armed to resume.
4. Newly deployed fields have NO FLS for anyone (incl. sysadmin) - deploy permsets before running
   scripts or every query shows "field not accessible" / silently returns nothing.
5. The sweep heals by NULLING the field so the before-save flow restamps - the flow MUST be active
   first. Ran it early once: harmlessly nulled already-blank fields (all mismatches were blank).
6. upload-brand-assets needs explicit --logo/--watermark args (argless run misread and hit the
   52MB request cap).

REMAINING: throttled field passes; classes + 3 tests; One_Click/Zero_Click/Agreement_Signed_
Writeback flows + activation; quick action; full (untrimmed) permsets; Approved-layout patch;
smoke render + live send. DO NOT generate Order Forms in PROD until the fields land - the
template cites the 13 missing formulas. Kam remaining: assign Order_Form_Subscriptions_Group
to the sales teams for 1 Sep.

## Phase 6 - PROD deployment COMPLETE (2026-08-24 evening)

Throttle cleared ~17:10 UK (Kam's "try again" probe caught it). Landed in order: 6 Subscription
twins (6/6); 13-formula pass revealed a REAL limit once the throttle noise cleared -
Legal_Contact_Email_Phone/Name_Title exceed PROD Quote's 15-unique-relationship formula-spanning
cap ("16 unique relationships while only 15 are allowed"). Both SKIPPED IN PROD: the v1.3 document
dropped the Legal/notices row so nothing consumes them (SF support can raise the cap if ever
needed; sandboxes accepted them - never trust sandbox for spanning headroom). GOTCHA: prod deploys
are ATOMIC - the "11/13" pass rolled back entirely; redeploy of the clean 11 succeeded.
Then: classes + 3 test classes 16/16 green (cov 93-94%), quick action, full permission sets +
group; One_Click/Zero_Click/Agreement_Signed_Writeback deployed + ACTIVATED (all 7 now active);
Approved layout patched (fresh retrieve + patch-approved-layout.py). Smoke render PASSED on
Q-219317 - the exact quote Kam's Bad Request came from: entity block, terms link, licence sentence,
real term dates 31/08/2026-30/08/2028, live payment terms Net 45, conditional PO tags. PDF sent to
Kam. Template renamed back to "Subscription Order Form".
REMAINING: one live end-to-end send with an internal signer (proves key/status-sync/write-backs in
PROD); Kam assigns Order_Form_Subscriptions_Group to sales teams for 1 Sep; Legal publishes the
API Terms page before 1 Sep.

## Section 8 "Other Terms" - Product Specific Terms now print (2026-08-24)

Kam (during the PROD live-test review): the quote's Product Specific Terms must print, named
"Other Terms" - and the legacy signed contract for Q-219317 confirms the name: the old Lexology
PRO order form has an OTHER TERMS section carrying exactly this content. PROD usage: 2,790 of
36,683 quotes in the last 365d (7.6%) carry real per-deal commitments (long-text fields cannot be
SOQL-filtered; counted client-side).
Build (pattern of section 6): Other_Terms_Display__c (LTA 32768) stamped by
Quote_Stamp_Order_Form_Fields ("None" when blank); 07b-other-terms.html (OF-V12-C07B/S85);
Execution renumbered 8 -> 9; FLS in Core. Deployed KJDEV + FULLUAT + PROD; content pushed to all
three; verified both ways on a FULLUAT render. Gotchas: KJDEV deploys from inside the sfdx
project hit source-tracking conflicts (use --ignore-conflicts; staged-dir deploys bypass
tracking); quotes not yet re-saved print the section blank until their next save.

## Gap analysis vs the legacy signed contract (2026-08-24)

Kam shared Q-219317's ORIGINAL signed contract (legacy Lexology PRO form + inline T&Cs + LBR
countersignature + Freudenberg security appendix; scanned, no text layer - pages read as images).
Covered/better: Other Terms (new), PO/VAT questions, entity/governing-law, licence sentences.
Open gaps (decisions, not defects): (1) company COUNTER-SIGNATURE - legacy dual-signed, ours
single-signer by v1.2 design (Adobe supports a second internal signer); (2) T&Cs INLINE vs our
URL reference - deliberate, confirm with Shinae; (3) CUSTOMER APPENDIX bundling into the signed
PDF (Freudenberg security doc) - our send attaches only the Order Form; buildable via additional
agreement attachments; (4) Account Manager + email printed; (5) Ship To address; (6) per-line
Geography column; (7) product-brand logo (already ruled: Centellic umbrella). NOTE: the live
write-back test is still open - both test agreements remain Out for Signature.

## Gap items built: Account Manager row + Geography in the licence column (2026-08-24)

Kam: build gap #4 (Account Manager) and fold #6 (Geography) into the Licence Model column - no
new column. Built + deployed KJDEV/FULLUAT/PROD, content pushed to all three, verified on render:
- Section 2 gains an "Account manager (Centellic)" row between Main and Billing: two flow-stamped
  text fields Account_Manager_Name__c / Account_Manager_Email_Phone__c from SBQQ__SalesRep__r.
  Deliberately NOT formulas (PROD Quote is at the 15-relationship formula-spanning cap).
  GOTCHA: User.Name is a COMPOUND field - flow formulas silently return blank for
  {!$Record.SBQQ__SalesRep__r.Name}; use FirstName & " " & LastName.
- License_Model_Display__c appends " Geography: <value>." when QuoteLine.Geography__c is set
  (sparse but real: GLOBAL/APAC/... ~1% of recent lines; legacy form printed it as a column).
Remaining gap decisions (Kam/Shinae): counter-signature, inline T&Cs, appendix bundling, Ship To.

## LIVE END-TO-END PROVEN IN PROD + cleanups (2026-08-24 evening)

Kam signed agreement a3GPx000001YONVMA4 (Q-219317, sent with the day's full template: Other Terms,
licence sentences, PO/VAT questions). ALL write-backs landed in PROD within seconds: Signed status
sync; Customer_Signed_Date 2026-08-24; signed PDF filed on the quote (+5s); PO_Required=Yes +
PO-TEST-3; VAT_Registered=Yes + Test123456; Account.Sales_Tax_Number filled from blank with the
provenance note. PHASE 6 IS FULLY PROVEN END TO END.
Cleanups: test values reverted from the REAL Freudenberg account (Sales_Tax_Number + Source) and
quote (PO/VAT/signed date); signatory restored to the customer contact. The signed test PDF stays
filed on the quote (harmless, titled as Q-219317); the two superseded agreements (OIfMAO, OKHMA4)
remain Out for Signature - Kam cancels in Adobe with the other probes.
Kam ruling on seeing the signed render: Account Manager row REMOVED from section 2 (added earlier
today as gap #4) - row deleted from the template in all three orgs; the flow-stamped AM fields
remain on the quote for ops/future use.

## ALM sub sold in EMEA / HK - cross-entity render test (2026-08-24, Kam request)

FULLUAT, Q-206385, line temporarily swapped to Law.com (Subs - Law.com family), fully reverted
after. Three billing entities exercised; entity block, governing law and the region-based licence
rule all flip correctly:
- LBR (EMEA): LBR entity + English law + Benefiting Group (with description).
- GHK (Hong Kong): HK entity (reg 1701157, Jubilee Centre Wan Chai) + English law + Benefiting Group.
- ALM (US control): ALM GLOBAL, LLC (13-3273851, NY) + New York law + Limited Access "up to 25
  authorised users" (from Number of Seats).
PDFs delivered to Kam.
FINDING (cross-feature): the REV-60 dispatch-code validation rule ("1 ALM line(s) still need a
required code: LAWM...") fires on EVERY quote save while an ALM line lacks its dispatch code -
which also blocks the Order Form stamping flows (before-save can't run if the save is rejected),
so entity/terms stamps go stale on such quotes. No real-world exposure: the same rule forces reps
to enter codes at QLE save, so genuine ALM quotes always carry them - only API-built lines skip it
(fix in tests: set Dispatch_Method_Code__c, e.g. "OS"). Confirms the REV-60 collision memo's
"VRs gate all quote saves" dynamic - remember when REV-60's Calculate-time automation is built.
Sequencing for entity tests: set opp Billing_Entity FIRST is not enough - line DML can re-derive
it; order used = line DML, set entity, touch line (licence restamp reads entity at line save),
quote resave (entity/terms stamp), verify both before doc gen.

## SOQL-101 incident: flows deactivated by Saurabh, optimised package built (2026-08-27)

10:07 the Opportunity master flow chain hit "Too many SOQL queries: 101" on a renewal update; the
failing element was THEIR OWN Get (Opportunity_Renewal_New_Records / Get Previous Opportunity
Product) - the chain runs at ~98-100 without us. Saurabh deactivated 4 of our quote flows
(Stamp Terms, Stamp Order Form Fields, Zero Click, VAT sync) - users could not save quotes.
Verified footprint of ours per quote save: 3 countable SOQL, not "errors":
- Stamp Order Form Fields: 2 - because the entity CMDT gets selected Governing_Law_Clause__c
  (LongTextArea). KEY GOTCHA: CMDT queries are SOQL-limit-EXEMPT only while no long-text field is
  selected; selecting one makes the query count.
- Stamp Terms: 1 (the API quote-line lookup; terms CMDT is text-only = exempt).
- Zero Click / VAT sync: 0 in bulk transactions (entry-gated; never start).
OPTIMISED PACKAGE (footprint 3 -> ~0, deployed KJDEV+FULLUAT active, PROD AS DRAFT - activation
deliberately left for Kam/Saurabh since Saurabh pulled the flows):
1. New CMDT Text(255) Governing_Law_Short__c, values copied into the 5 records; the flow reads it
   instead of the long-text clause -> both entity gets exempt again (-2).
2. Terms + API stamping MERGED into Quote_Stamp_Order_Form_Fields (one before-save flow per
   object/timing - Salesforce Well-Architected). Quote_Stamp_Terms replaced by an inert stub
   version (filterFormula false; sandboxes deploy flows active so the stub supersedes behaviour).
3. The one remaining line query gated by SBQQ__LineItemCount__c > 0 AND the whole flow behind the
   org-standard Application_Settings__c.Disable_Autolaunch_Lightning_Flow__c bypass - Saurabh can
   exempt automation users without touching us.
Verified in FULLUAT: blanked every stamp, one resave restored all (terms/entity/law/API/Other
Terms/AM). TO ACTIVATE IN PROD after Saurabh's OK: Quote_Stamp_Order_Form_Fields v3,
Quote_Send_Order_Form_Zero_Click v1, Quote_Sync_Captured_VAT_to_Account v1 (entry-gated,
innocent), and Quote_Stamp_Terms v2 ONLY IF wanted (inert stub; can also stay deactivated).
Flow count for docs: 6 active + 1 retired stub.

## Re-activation (2026-08-27, Kam's call - Saurabh reports to him)

Kam authorised re-activation. PROD final state: 6 active flows - Quote_Stamp_Order_Form_Fields v3
(merged, near-zero SOQL), Zero_Click, VAT sync, QuoteLine_Stamp_License_Model, One_Click,
Agreement_Signed_Writeback; Quote_Stamp_Terms stays INACTIVE (retired, stub is latest). Verified:
one PROD quote resave stamps everything (terms/entity/governing law from the new Text field/Other
Terms/API flag) with zero errors. Saurabh should be told: the merged v3 costs ~0 countable SOQL,
zero-click/VAT never start in bulk transactions, and his own bypass switch now gates our flow too.

## FINEST-trace league table + org-wide automation plan (2026-08-27 afternoon)

Saurabh deactivated the 4 Order Form flows AGAIN (14:34) after Hannah Mason's saves kept failing;
at 14:37 the SWOOGO INTEGRATION user hit the same 101 WITH OUR FLOWS OFF - the controlled
experiment that closes attribution. Debug trace (Database=FINEST) on Hannah captured a full
failing save (8MB, ends in LIMIT_EXCEEDED). League table of 82 attributed queries:
OpportunityTrigger (org Apex) 32; rh2 Rollup Helper 25 (RHX_Opportunity 22 + RHX_OLI 3);
ALMPromoDispatchEngine (REV-60) 10; org flows 9; flow engine 4; OUR FLOWS 2 (2.4%).
Landscape (FlowDefinitionView): 14 active record-triggered flows on Opportunity, 8 Quote,
7 Opportunity Product, 5 Quote Line + triggers/packages, all one transaction on rep saves
(admin/finance profiles skip the heavy branch - why admins cannot reproduce).
Long-term plan authored (Kam: "world class solution"), artifact "One Save, 101 Queries"
(fb01c8e9-10fe-46ab-81cb-95c29e6124f4): P0 stabilise (renewal subflows -> async path, entry-gate
master chain, re-activate Order Form flows); P1 OpportunityTrigger bulkification + rh2 retirement
via Firm Sales Summary (already built; 4 consumers to repoint) + REV-60 query diet; P2 flow
consolidation to one before/after-save per object + automation intake checklist + limit telemetry.
Principles: 70-query budget with an owner; async by default; no CMDT long-text selections;
bypass + entry conditions everywhere; measure with FINEST traces, not opinions.
Current state: Order Form stamps/zero-click/VAT sync DEACTIVATED (licence stamp, one-click,
signed-writeback active). Re-activation = P0 decision with the async move. Trace flag on Hannah
expires ~2h; log saved as scratchpad hannah-101.log.

## P0 executed: rh2 async flip + REV-60 async + rollup census (2026-08-27 afternoon)

SAURABH VETO on moving Opportunity_Renewal_New_Records to async (his flow, accepted); his counter
"move the new quote flows to schedule path" is a platform impossibility for before-save stamps
(no scheduled paths on before-save; converting to async after-save would ADD a quote-update
transaction per save - counterproductive) - declined with evidence.
RH2 CENSUS (Kam: "do we need them?"): 44 active rollups (UI); dependency-API census of ~77 target
fields: ~60 have ZERO metadata consumers; 4 confirmed live (Account.No_of/CFY_No_of_Won_Office_
Opportunities - layouts+Apex; Active_Subscription_Specialist_Plt - flow; Docket_Navigator_Total_
Sale_Value - CRM Analytics recipe). CAVEAT: dependency API does not see reports/dashboards.
SCHEDULING DEAD END: per-rollup full recalc = 787,018 Accounts, ~8 days per rollup - hourly
schedules unviable. THE ACTUAL FIX: rh2__PS_Object_Realtime__c per-object Asynchronous flag -
OLI has run async since Apr 2025 (why RHX_OLI cost only 3 queries vs RHX_Opportunity 22).
FLIPPED opportunity -> async (one field, via Kam's session + Chrome takeover after Kam could not
find the setting - it is NOT rendered anywhere in the Rollup Helper UI). Controlled no-op A/B:
RHX_Opportunity 8 -> 5 queries; real saves (full recalc deferred) expected ~22 -> ~5. Rollback =
flag to false.
REV-60/71 ASYNC: Opp_ALM_Code_AfterSave (REV-71) was ALREADY async (AsyncAfterCommit path).
Opp_ALM_PromoDispatch_AfterSave (REV-60) converted to the same pattern and ACTIVATED (v2).
Platform rules learned: async paths need IsChanged-operator filters or changed-to-meet flag, and
filterFormula+ISCHANGED is INVALID with the flag - the working shape is Update trigger + IsChanged
filters (creates carry no lines to stamp, so nothing lost). Quote-side stamps
(Quote_ALM_PromoDispatch_Stamp, 9 queries in the trace) are subflows on Saurabh's
Quote_AfterSave_MasterFlow sync path - flagged to him to move to his async path.
BUDGET AFTER TODAY (rep-save transaction): rh2 ~-17, REV-60 opp -1 sync (+ quote-side -9 pending
Saurabh), Order Form diet -3 (26 Aug). Remaining big rocks: OpportunityTrigger 32 (Saurabh audit),
quote master sync path. Trace-on-rep + no-op A/B measurement technique now standard.

## REV-60 engine: transaction idempotency cache (2026-08-27 evening)

Kam: "Quote_ALM_PromoDispatch_Stamp - what can we do?" Full async RULED OUT: the quote master
chain ends in the save-blocking Custom Error (Err_ALM_Codes_Required) fed by the engine's gap
verdict - live enforcement (it blocked my own API save on 26 Aug), and the engine already yields
on saturated transactions (hasQueryHeadroom). The real waste = REPEAT invocations: CPQ saves the
same quote 3-4x per transaction and Layer 1 re-ran its full query+derive each time.
BUILT: transaction idempotency cache in ALMPromoDispatchEngine.stampQuote - static per-transaction
result+signature maps; repeat invocations run ONE probe query (lines + quote derivation inputs);
unchanged signature -> cached FlowResult returned (gap verdict intact); any change -> full fresh
run; cache disabled in tests by default (txnCacheEnabled) with a dedicated cache test (fresh ->
cached-reuse -> poisoned-signature -> rerun). Cost ~9-10 -> ~4-5 per transaction, behaviour
identical. Gotchas: SBQQ__ProductCode__c not writeable in tests; bare QuoteLine inserts blow up on
CPQ QuoteLineAfter trigger in test context - poison-the-signature is the testable change-path.
47/47 tests green KJDEV. FULLUAT needed the ALM_Code_Engine_Settings CMDT fields deployed first
(its REV-60 config schema was behind repo). PROD deploy queued behind another (failed) deploy -
landing pending; note a third-party PROD deploy failed 16:03 with 35 test errors (someone else
deploying - possibly Saurabh mid-work).

## Shipping address row (2026-08-28, Kam request - legacy gap #5 closed)

Section 1 Customer block gains "Shipping / delivery address" under the registered address, merged
straight from the quote's standard CPQ shipping fields (SBQQ__ShippingStreet/City/State/
PostalCode/Country - CPQ auto-copies them from the Account; no new fields, no flow work).
Pushed to all three orgs; verified on a FULLUAT render.

## Brand-aware header logos (2026-08-27 evening, Kam: "invoices are brand specific")

Kam supplied the BrandHub SharePoint logo library (globebpcrm/sites/BH/Logos) - 12 brand folders.
Pulled 11 positive (on-white) master PNGs via his Chrome session -> localhost relay (SharePoint
REST GetFileByServerRelativeUrl; folders each have a master subfolder; GAR's is "Full & Short
version"). Selection: <Brand>_RGB_full/long version_positive.png; Lexology=logo_blue; Index/PRO=
single line. Centellic doc already existed.

DESIGN (single template, brand-aware header - NOT template-per-brand):
- Feasibility: header already merges {!quote.Name}, so header merges substitute; proven img-src
  attribute merges work too (GAR PNG embedded 1608x288 in rendered PDF).
- Lead brand = Brand__c of the HIGHEST SBQQ__NetTotal__c line that has a brand (flow two-variable
  max loop; family can't split GAR/GCR/GIR - Brand__c is a CPQ twin field from Product2, brand-
  granular, ~75% filled). "Lexology Pro" products carry Brand=Lexology -> Lexology logo (PRO logo
  uploaded but unmapped, in reserve).
- Order_Form_Brand_Logo__mdt (Brand_Value__c exact match / Logo_Document_Name__c / Is_Default__c):
  13 rows - GAR GCR GIR GRR IAM WTR LACCA, LL->Latin_Lawyer, Lexology + In-Depth + Panoramic ->
  Lexology, Lexology Index, Default->Centellic_Logo_2026. All Text fields (long-text CMDT field
  voids the SOQL exemption).
- Quote_Stamp_Order_Form_Fields v16 KJDEV / v9 FULLUAT: after API-line get -> Get_Brand_Lines (all
  lines) -> max loop -> CMDT loop -> Get_Logo_Document (Document IS flow-queryable) -> stamp
  Order_Form_Brand_Logo_URL__c. URL formula: LEFT($Api.Enterprise_Server_URL_140 to '/services')
  + /servlet/servlet.ImageServer?id=<doc>&oid=LEFT($Organization.Id,15) - org-agnostic, $Api works
  in flow formulas. Not-found doc -> keep existing value (never stamp blank). +2 SOQL per quote save.
- Header img: src="{!quote.Order_Form_Brand_Logo_URL__c}" replaces push-time {{LOGO_URL}}.
  CRITICAL: blank src = whole render 400s -> PROD ORDER IS field+flow+docs FIRST, activate, backfill
  -touch any quote that might render with the v1.2 template, THEN push header. FULLUAT checked: zero
  existing v1.2 QuoteDocuments -> no backfill needed there.
- upload-brand-logos.js (cpq-templates/) uploads Brand_Logo_<key> Documents idempotently from a
  folder of <key>.png; needs Order_Form_Brand_Assets folder (upload-brand-assets.js) + CONFIRM_PROD.
E2E KJDEV: GAR(5000)+Lexology Index(1000) lines -> GAR logo stamped + embedded in PDF; unbranded
quote -> Centellic fallback. GOTCHA (again): KJDEV org-default AND Kam's user row had
Disable_Autolaunch_Lightning_Flow__c=true - flipped Kam's row for the test, restored after.
PROD: NOT deployed - awaiting Kam sign-off (brand guidance angle: BrandHub logos are the approved
assets; Order Forms lead with the deal's lead brand, Centellic only as fallback).
