# Preflight: Full UAT (HR to Salesforce employee sync, Phase 1)

Run: 7 September 2026, read-only. Operator: Kamyar Jannati. Brief: Claude_Code_Brief_HR_to_Salesforce_Phase1.md v2.
Working files: `scripts/hr_sync_phase1/preflight/` (describes, flow retrieves, sbaa dumps, item 7 script and output).

## Verdict

Full UAT is usable for the rehearsal under the sandbox exception Kam approved (stale copy, log-and-skip missing Ids). Four findings change the brief and are listed first. No blocker.

1. **Manager_Email__c on User is a formula, not a writable field.** It mirrors Manager.Email. It cannot be written and does not need to be; it updates itself when ManagerId changes. Section 5.1 of the brief lists it as a field to write. Remove it from the change set and keep it only as a verify column.
2. **Contact.Employee_Number__c is 10 characters.** HR Employee IDs are at most 7, so no truncation risk, but the brief should record the length.
3. **D3 is moot for this extract.** Longest Business Title is 60 characters, under both User.Title (80) and Contact.Title (128).
4. **The flag clear only works as System Administrator.** Validation rule Not_at_Company_Flag blocks any edit to a contact whose Not_at_Company_Checkbox__c was true unless the running user's profile is System Administrator, Custom: Fin/Ops/HR, B2BMA Integration User or Custom: Data Management, or holds the By_pass_not_at_company_validation_in_contact_object permission. Kam's Full UAT user is System Administrator, so the run passes. The bulk job must run as Kam (or another exempt profile) in production too.

## 1. Org verification

| | Full UAT | Production (for reference) |
|---|---|---|
| Alias | FULLUAT | PROD |
| Org Id | 00DAd00000CZR4rMAH | 00D6g0000081IOgEAM (matches brief) |
| Username | kamyar.jannati@lbresearch.com.fulluat | kamyar.jannati@lbresearch.com |
| Instance | https://lawbusinessresearch--fulluat.sandbox.my.salesforce.com | |
| Status | Connected, API 67.0 | Connected |
| Running user profile | System Administrator | |

KJDEV (00DAe00000D35gVMAR) is also connected but holds no production data; not used.

## 2. Refresh date

Full UAT last refresh completed **8 April 2026** (SandboxProcess on production; earlier copies Dec 2025, Oct 2025, Sep 2025 are deleted). Five months older than the 7 Sep 2026 mapping.

Id resolution of the mapping against Full UAT:

| | In scope | Found | Missing | Found but inactive |
|---|---|---|---|---|
| Users (confirmed tier, active) | 412 | 355 | 57 | 19 |
| Contacts (primary) | 744 | 587 | 157 | n/a |

All 57 missing users were created in production after the refresh (14 Apr to 4 Sep 2026). 155 of the 157 missing contacts were created after the refresh; the other two carry 2016 CreatedDate on new-format Ids (backdated migration loads) and also post-date the copy. The 19 inactive users are older Ids that are active in production. Nothing in the mapping is absent from production.

Decision (Kam, 7 Sep): rehearse on the stale copy. Step 1.3 logs and skips missing or inactive Ids when the target is Full UAT; the hard abort stands for production. The mapping itself reconciles to the brief: 412 users, 744 contacts.

## 3. Field describes

### User

| Field | Exists | Type | Length | Updateable | Note |
|---|---|---|---|---|---|
| Title | yes | string | 80 | yes | |
| EmployeeNumber | yes | string | 20 | yes | |
| Employee_Code__c | yes | string | 255 | yes | Unrelated Opportunity.Employee_Code__c also exists; not touched |
| ManagerId | yes | reference | 18 | yes | |
| Manager_Email__c | yes | string (formula) | 1300 | **no** | Calculated; equals Manager.Email on every sampled user. Drop from the write set |
| Email, Name, IsActive, SystemModstamp, LastModifiedById | yes | | | read-only use | verify and baseline columns |

### Contact

| Field | Exists | Type | Length | Updateable | Note |
|---|---|---|---|---|---|
| Employee_Number__c | yes | string | 10 | yes | HR max is 7 |
| Title | yes | string | 128 | yes | label "Job Title" |
| Not_at_Company_Checkbox__c | yes | boolean | | yes | guarded by VR Not_at_Company_Flag (see 4) |
| No_Longer_w_Company__c | yes | boolean | | yes | |
| ADvendio__LeftCompany__c | yes | boolean | | yes | |
| LID__No_longer_at_Company__c | yes | picklist (Not at Company, Ignore) | | yes | out of scope; drives flows and VR |
| Not_at_Company_Flag_Status__c | yes | formula | | no | display only |
| DoNotCall, HasOptedOutOfEmail, No_Postal__c, ReportsToId | yes | | | out of scope | baseline columns for side-effect check |

HR extract (933 rows): Employee ID is text in every cell, 1 to 7 characters, none with a leading zero, 137 non-numeric (HK-prefixed codes such as HK578 are genuine HR IDs, not legacy values). Business Title max 60 characters.

## 4. Automation on User and Contact

### Record-triggered flows (FlowDefinitionView, Full UAT)

| Object | Flow | Active | Trigger | Relevance |
|---|---|---|---|---|
| User | ManagerIdUpdation | yes (v active) | after update, ManagerId is null | Restores prior ManagerId when it is cleared. Script never clears ManagerId: no collision |
| User | Groove_licenses | yes | after update | Reads IsActive and Clari Groove licence fields only |
| User | Email_alert_to_new_user | yes | after create/update | Reads IsActive; new-user email |
| User | Salesforce_User_License_Threshold_Notification | yes | after create/update | Licence counts; not field-specific |
| User | Create_Contact_from_User | **no** in Full UAT | after create | Would copy ManagerId to Contact.ReportsToId at creation only |
| Contact | Contact_Object_Create_Edit | yes | after create/update | "Not at Company Flag" branch forces DoNotCall, HasOptedOutOfEmail, No_Postal__c true when Not_at_Company_Checkbox__c is true OR LID__No_longer_at_Company__c = "Not at Company". Never reverts. Basis of D4 |
| Contact | Not_at_Company_Checkbox_Update | **yes, v5 active** (v6 Draft is what the repo holds) | after update, **only when LID__No_longer_at_Company__c changed** | Sets the checkbox true/false from the LID value. Because it fires only on a LID change, clearing the checkbox does not re-trigger it. Basis of D5 |
| Contact | Contact_Creation_Update_Set_Assistant_Email_Opt_Out_Fields | yes | before create/update | Sets HasOptedOutOfEmail for five named external email domains; not applicable to house contacts |
| Contact | Notify_Groove_on_Contact_Created_Flow | yes | after create/update | Groove notification; no in-scope field |
| Contact | Update_Account_Organisation_Type_from_Contact_Organisation_Type | yes | after create/update | Organisation type only |
| Contact | Notify_Groove_on_existing_Contacts_Flow | no | | |

Escalate_Case (autolaunched, active) reassigns cases to Owner:User.Manager_Email__c / $User.ManagerId. Consumer of the manager batch (D2). Other repo flows that read Owner.ManagerId (Opportunity_Object_Create_Edit, Opportunity_Renewal_New_Records, Send_Handshake_SDR_Notification, QuoteAndOpportunityApprovalCustomNotification) stamp or notify the owner's manager at the time of a later Opportunity save; a correct manager is the intended outcome, not a side effect to guard.

### Apex triggers (all managed packages, all active)

Contact: rh2 PS_Contact + PS_Contact_Describe_Async (Rollup Helper), LID ContactTrigger (LinkedIn Sales Navigator), pi LogContactChange (Pardot), CRMfusionDBR101 DB_ContactTrigger (DupeBlocker), Validity_Verify contact, pw_cc ValidateContactBeforeSave (AddressTools), CventEvents ContactTrigger, DaScoopComposer normalizeContactPhone (Groove), DOZISF ContactTrigger + OpsosContactTrigger (ZoomInfo).
User: echosign_dev1 SyncEchoSignUser (Adobe Sign), DaScoopComposer GrooveAssignPermissionSet.

DupeBlocker Contact scenarios (both deployed): Match-on-update action is "Report Duplicate" for both, so a Title or Employee_Number__c update cannot be blocked or redirected; it can only log a duplicate warning where a match already exists. UNABLE_TO_LOCK_ROW risk on bulk Contact updates comes from this trigger stack; sequential 200-row files per the brief.

No ADvendio automation on Contact found (no ADvendio trigger or flow on Contact in Full UAT). ADvendio__LeftCompany__c is a plain checkbox here.

### Validation rules (10 active on User/Contact)

| Object | Rule | Touches in-scope field | Effect on this run |
|---|---|---|---|
| Contact | Not_at_Company_Flag | Not_at_Company_Checkbox__c (PRIORVALUE = true) | Blocks every edit to a flagged contact unless the running user is System Administrator / Custom: Fin/Ops/HR / B2BMA Integration User / Custom: Data Management, or holds By_pass_not_at_company_validation_in_contact_object, or Application_Settings__c.Disable_Validation_Rules__c is on. **Run as Kam (System Administrator).** |
| Contact | Not_at_Company_Flag_uncheck | LID__No_longer_at_Company__c | Blocks unchecking the LID value for non-exempt users. LID is out of scope; not triggered |
| Contact | Contact_must_have_an_Account, Stop_Contacts_Moving, Contact_Name_Address_cannot_be_changed, Restrict_users_from_changing_Address, Prevent_user_from_changing_email, FIist_Name_Cannot_be_Blank, Salutation_Mandatory | none | Not triggered by Title / Employee_Number__c / flag edits. Salutation_Mandatory could fail a contact that already lacks a salutation if it evaluates on every edit; watch for it in the failure file |
| User | Assign_a_Groove_core_license | none | Groove licence fields only |

## 5. sbaa (CPQ Advanced Approvals) and the manager hierarchy (D2)

| | Count |
|---|---|
| Approval rules | 495 (325 active; 481 on SBQQ__Quote__c, 11 ADvendio__MediaCampaign__c, 3 Opportunity) |
| Rules using sbaa__ApproverField__c (approver resolved from a field on the record) | 3, **all inactive** (1 × Opportunity_Owner_Manager_ID__c, 2 × x20_Approver__c) |
| Approver records | 110 (98 named user, 13 group, 2 with NextApprover) |
| Approval chains | object exists; no rule resolves through the manager hierarchy |

Every active rule points at a fixed Approver record (named user or group). sbaa__Approver__c has no dynamic "manager of submitter" type in this org. **D2 clears on the sbaa side**: changing User.ManagerId cannot change who approves a quote. Remaining D2 consumer is Escalate_Case routing (section 4), which is the intended effect of a correct manager.

Side note for the tech-debt register: 29 approver-record slots point at users who are inactive in Full UAT (Angus Codd ×6, Sarah Maundrell ×2, Richard Morris ×2, Andrew Teague ×2, Chris Black ×2, and 15 others). Some are active in production (e.g. Sarah Maundrell, James Dartford appear in the 19 inactive-in-sandbox list); the rest are worth a production check outside this brief.

## 6. Report, dashboard and list-view dependencies

Full UAT holds 6,131 reports (335 folders), 344 dashboards and 528 list views on User/Contact/Lead/Opportunity/Case/Account. 6,099 reports resolve to a retrievable folder; 32 sit in users' Private Reports folders and cannot be retrieved by the Metadata API.

Retrieved 6,977 components (6,099 reports, 344 dashboards minus 15 managed-package dashboards the API could not return, 528 list views) into `preflight/reports_FULLUAT/` and parsed every report, dashboard and list view for the in-scope fields, separating display columns from filters and groupings. Raw hit list: `preflight/report_grep_hits.txt`.

| Field | Display column only | Used in a filter or grouping | Assessment |
|---|---|---|---|
| User.EmployeeNumber | 11 reports, all Finance **SUN Report** variants (SUN_Report_for_Auditors, SUN_Report_Last_Month_ONLY, SUN_Report_Legal_Information_Only, SUN_Report_MBL_only, Copy_of_SUN_Report_Commissions, GTDT_Prior_Period_Cancellations, SUN_Report_Swoogo_Registrations and four copies) as Opportunity Owner.EmployeeNumber | 0 | **Needs a Finance answer before Gate 1.** The SUN reports are the extract to the SUN finance system. If Finance keys the import or commission mapping on the owner's Employee Number, replacing the legacy A/E/G codes with HR IDs changes what SUN receives for about 309 users. No filter breaks, but the downstream consumer may. |
| User.Employee_Code__c | 1 (Employee_Report_561, unfiled public) | 0 | Harmless. The other four hits are Opportunity.Employee_Code__c, a different field. |
| User.Manager_Email__c | 2 (Open_Pipeline_This_Month_Tabular, Employee_Report_561) | 0 | Harmless; formula updates itself. |
| User.ManagerId (Owner Manager) | 52 | **56** reports, dashboards and list views filter or group on the owner's manager by name: the whole ALM_IS_New_Sales Team Dashboard folder (Owner Manager = Khris Fenton, 15 reports), GTM renewal reports (Fenton, Silveira, Harlan), PipelineTracker groupings by User Manager, Adobe agreements (Matthew Bridgewater), and **ALM_Commission_Report** (Owner.Manager.Manager contains green, fenton, mcreynolds, harlan, silveira). List view Active_Users_with_no_Managers. | **Expected effect of the manager batch, but visible.** The about 92 manager changes move opportunities between team dashboards and can change who appears in the ALM commission report. D2 should say so and the dry run should list, per changed user, which manager-name filters they leave and join. |
| Contact.Employee_Number__c | 5 (Customer Care case reports: Escalated_Cases, WNS_Only_Open/Closed_cases, CRM_Support_Case) | 0 | Beneficial; the column fills in. |
| Contact.Not_at_Company_Checkbox__c | 1 | 1 (BD_and_Marketing_Contacts_Italy filters = false) | Negligible; the cleared contacts join one BD list. |
| No_Longer_w_Company__c, ADvendio__LeftCompany__c | 0 | 0 | No consumers. |
| User.Title (Owner Title) | 12 | 4: list view Customer_Success_Team (Title contains Customer Success / Customer Support), two LexPro manager reports (Owner Title not contains Success), Copy_of_Active_Subs_Anderson_Young (contains Key Account Manager) | Membership can change for the about 194 title updates. Dry run should evaluate these four predicates before and after for every changed user and list the movers. |
| Contact.Title | 276 | 35, all persona filters aimed at external contacts (In House / Legal / Counsel / HR / IP keyword lists) | House-account contacts already sit in these pools; new HR titles containing HR, Legal, Counsel, Business, Head, Ops could pull internal staff into BD persona lists (for example Lexology_PRO_BD_HR_Personas, Recruiting_HR_Contacts_Law_Firms). Low impact, but worth a count in the dry run: changed contacts whose new title matches any of the 35 predicates. |
| Legacy EmployeeNumber codes as filter values | 0 | 0 | No report or list view filters on a specific legacy code. |

Not retrievable: 32 reports in users' Private Reports folders. Production preflight repeats this section against production metadata, which may have moved since April.

## 7. The flagged contacts (D4, D5)

8 of the 587 found contacts carry a flag, all via Not_at_Company_Checkbox__c only (No_Longer_w_Company__c and ADvendio__LeftCompany__c are false on every found contact). The brief's 9th is presumably among the 157 contacts missing from the sandbox; production preflight will show it.

| Id | Name | Account | DoNotCall | Email opt-out | No_Postal | LID |
|---|---|---|---|---|---|---|
| 0034L00000aHhXWQA0 | Joyce Ng | Law Business Research Asia Ltd | 1 | 1 | 1 | Not at Company |
| 0034L00000aHhYiQAK | Victoria Arnold-Rees | Law Business Research Ltd | 1 | 0 | 1 | Not at Company |
| 0034L00000aHhZtQAK | Jonathan Derouet | Law Business Research Ltd | 1 | 1 | 1 | Not at Company |
| 0034L00000aHhbBQAS | Ken Fitzgerald | Law Business Research Ltd | 1 | 1 | 1 | Not at Company |
| 0034L00000aHhdVQAS | Ignacio Abella Gainza | Law Business Research Ltd | 1 | 1 | 1 | Not at Company |
| 0034L00000aHhecQAC | Cara Kramar | Docket Navigator | 1 | 1 | 1 | Not at Company |
| 0036g000013e6cTAAQ | Nick Townsend | Law Business Research Ltd | 1 | 1 | 1 | Not at Company |
| 003Px00000cqu0tIAA | Scott Pitman | Alm Ga | 1 | 1 | 1 | Not at Company |

What this means:
- **D4 confirmed.** All 8 have the forced opt-outs. Clearing the checkbox leaves them opted out. Worse, LID__No_longer_at_Company__c still reads "Not at Company" on all 8, and Contact_Object_Create_Edit re-forces the opt-outs on every save while that is true. Reverting the opt-outs by hand would not stick until the LID value is also cleared.
- **D5 partly reassuring.** Not_at_Company_Checkbox_Update (active v5) fires only when the LID value changes, so the script's flag clear does not re-set the checkbox. The checkbox comes back only if LinkedIn re-sends "Not at Company", which it would for a genuine leaver. For these 8 current employees the LID value is simply stale.
- Recommendation for Gate 1: keep D4/D5 read-only in Phase 1 as the brief says, and put "clear LID on the 8/9, then revert the three opt-outs" as one Phase 2 item, done by a System Administrator so the Not_at_Company_Flag_uncheck rule does not fire.

Across all 587 found contacts: DoNotCall 12, HasOptedOutOfEmail 19, No_Postal__c 12. The 4, 7 and 4 not explained by the 8 flagged contacts are in the baseline and must not move.

Contact.Employee_Number__c today: 185 filled, 402 blank. User.EmployeeNumber: 205 filled, 150 blank; User.Employee_Code__c: 170 filled, 185 blank. Legacy alphanumeric codes present in both User fields (A-, E-, G-prefixed four-character codes, ALKF and similar); these are the values that any report or list view filter would be keyed on (section 6).

## 8. Data lengths and D3

No Business Title exceeds 80 characters; D3 produces zero skips on this extract. Keep the check in the script for future extracts.

## 9. Brief changes carried into v3 (applied 7 Sep)

- D2 wording: sbaa cleared; consumers are Escalate_Case routing, 56 manager-name report/dashboard/list-view filters and the ALM commission report.
- New D6 / Gate 1 question for Finance: does the SUN import or commission process consume Opportunity Owner Employee Number? If yes, EmployeeNumber must not change until Finance has remapped, or the legacy code moves to another field first.
- Step 1.5 dry run: add the filter-membership diff for the 4 User Title predicates, the manager-name predicates and the 35 Contact Title persona predicates.

- 5.1: remove Manager_Email__c from the write set (formula). Verify it as a derived column only. The "about 92" expected changes apply to ManagerId alone.
- 3 / 5.2: record Contact.Employee_Number__c length 10.
- 7 Guardrails: the Contact update must run as a System Administrator (or other profile exempt from Not_at_Company_Flag), and Application_Settings__c.Disable_Validation_Rules__c is not to be used as the bypass.
- Step 2.3: add Salutation_Mandatory and the DupeBlocker "Report Duplicate" warnings to the list of expected non-blocking messages in the failure file review.
