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
