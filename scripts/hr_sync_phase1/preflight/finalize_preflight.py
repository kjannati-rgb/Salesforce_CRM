"""Writes section 6 (report dependencies) into preflight_FULLUAT.md and applies v3 factual corrections to the brief."""
p = r"C:\sf-work\kjdev\scripts\hr_sync_phase1\preflight_FULLUAT.md"
s = open(p, encoding="utf-8").read()
old = "_Retrieve in progress; grep results to follow in this section._"
new = """Retrieved 6,977 components (6,099 reports, 344 dashboards minus 15 managed-package dashboards the API could not return, 528 list views) into `preflight/reports_FULLUAT/` and parsed every report, dashboard and list view for the in-scope fields, separating display columns from filters and groupings. Raw hit list: `preflight/report_grep_hits.txt`.

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

Not retrievable: 32 reports in users' Private Reports folders. Production preflight repeats this section against production metadata, which may have moved since April."""
if s.count(old) == 1:
    s = s.replace(old, new)
old9 = "## 9. Brief changes to carry into v3"
new9 = """## 9. Brief changes carried into v3 (applied 7 Sep)

- D2 wording: sbaa cleared; consumers are Escalate_Case routing, 56 manager-name report/dashboard/list-view filters and the ALM commission report.
- New D6 / Gate 1 question for Finance: does the SUN import or commission process consume Opportunity Owner Employee Number? If yes, EmployeeNumber must not change until Finance has remapped, or the legacy code moves to another field first.
- Step 1.5 dry run: add the filter-membership diff for the 4 User Title predicates, the manager-name predicates and the 35 Contact Title persona predicates."""
if s.count(old9) == 1:
    s = s.replace(old9, new9)
open(p, "w", encoding="utf-8", newline="\n").write(s)
print("preflight updated")

b = r"C:\Users\Kamyar.Jannati\Downloads\Claude_Code_Brief_HR_to_Salesforce_Phase1.md"
t = open(b, encoding="utf-8").read()


def rep(o, n):
    global t
    assert t.count(o) == 1, o[:50]
    t = t.replace(o, n)


rep("Date: 7 September 2026 (v2, revised same day after review)",
    "Date: 7 September 2026 (v3, corrected after Full UAT preflight; v2 earlier the same day after review)")
rep("| Manager_Email__c | Worker's Manager | The manager's User.Email queried from the target org, same rule as ManagerId | about 92 |",
    "| Manager_Email__c | (derived) | **Not written.** Preflight found it is a formula field mirroring Manager.Email (not updateable). Verify it as a derived column after the ManagerId batch | 0 (follows ManagerId) |")
rep("| Employee_Number__c | Employee ID | Write when blank or different | about 559 |",
    "| Employee_Number__c | Employee ID | Write when blank or different. Field length 10; HR max is 7 | about 559 |")
rep("| D3 | Business Title longer than the field (User.Title 80, Contact.Title 128) | Do not truncate silently. List them and skip until Kam supplies a short form |",
    "| D3 | Business Title longer than the field (User.Title 80, Contact.Title 128) | Do not truncate silently. List them and skip until Kam supplies a short form. Preflight: longest title in the 7 Sep extract is 60, so zero skips this time |")
rep("| D2 | Manager updates while CPQ Advanced Approvals (sbaa) may resolve approvers through the manager hierarchy, and Escalate_Case routes on the owner's ManagerId and Manager_Email__c | Build the manager changes as a separate batch. Do not apply to production until Step 0 has shown that no sbaa approval rule, approver or chain references User.ManagerId, and Kam has accepted that case escalations for the about 92 affected users will route to the new manager |",
    "| D2 | Manager updates: sbaa, case escalation and manager-keyed reporting | Build the manager changes as a separate batch. Preflight (Full UAT): no active sbaa rule resolves an approver through the manager hierarchy (all 325 active rules use fixed approvers; the 3 field-based rules are inactive), so sbaa clears. Remaining consumers: Escalate_Case routing, 56 reports/dashboards/list views that filter or group on Owner Manager by name (ALM_IS_New_Sales team dashboards, GTM renewals, PipelineTracker), and ALM_Commission_Report. Apply to production only after Kam has accepted those visible effects; dry run lists per user which manager-name filters they leave and join |\n| D6 | Finance SUN reports carry Opportunity Owner Employee Number (11 report variants incl. SUN_Report_for_Auditors and the Commissions copy). Replacing legacy codes with HR IDs changes what the SUN extract receives for about 309 users | Ask Finance before Gate 1 whether the SUN import or commission process consumes that column. If yes, hold the EmployeeNumber write (and D1 mirror) until Finance has remapped, or first copy the legacy code to a field Finance agrees to use |")
rep("- Every stop is a real stop. Print the report, end the turn, wait for Kam.",
    "- Every stop is a real stop. Print the report, end the turn, wait for Kam.\n- The Contact update must run as a user whose profile is exempt from validation rule Not_at_Company_Flag (System Administrator, Custom: Fin/Ops/HR, B2BMA Integration User, Custom: Data Management) or who holds By_pass_not_at_company_validation_in_contact_object. Kam's user qualifies in both orgs. Do not use Application_Settings__c.Disable_Validation_Rules__c as the bypass.")
rep("   - the D1 to D5 defaults restated.",
    "   - filter-membership diff: for every changed user, the 4 User Title predicates and the manager-name predicates found in preflight, before and after; for every changed contact, whether the new title matches any of the 35 Contact Title persona filters; list the movers;\n   - the D1 to D6 defaults restated.")
rep("GATE 1: stop. Kam reviews dry_run_report.md and the CSVs and confirms D1 to D5.",
    "GATE 1: stop. Kam reviews dry_run_report.md and the CSVs and confirms D1 to D6.")
rep("Stop immediately if failures exceed 1 percent or any failure is a validation rule or flow error; report the message verbatim.",
    "Stop immediately if failures exceed 1 percent or any failure is a validation rule or flow error; report the message verbatim. Expected non-blocking noise: DupeBlocker \"Report Duplicate\" warnings (its Contact scenarios only report on update) and Salutation_Mandatory on contacts that already lack a salutation.")
open(b, "w", encoding="utf-8", newline="\n").write(t)
print("brief v3 written")
