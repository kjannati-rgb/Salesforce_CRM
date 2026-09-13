"""Records the Step 2 (Full UAT rehearsal) findings in the brief as v4."""
b = r"C:\Users\Kamyar.Jannati\Downloads\Claude_Code_Brief_HR_to_Salesforce_Phase1.md"
t = open(b, encoding="utf-8").read()


def rep(o, n):
    global t
    assert t.count(o) == 1, o[:60]
    t = t.replace(o, n)


rep("Date: 7 September 2026 (v3, corrected after Full UAT preflight; v2 earlier the same day after review)",
    "Date: 8 September 2026 (v4, after the Full UAT rehearsal; v3 7 Sep after preflight; v2 7 Sep after review)")
rep("| Employee_Number__c | Employee ID | Write when blank or different. Field length 10; HR max is 7 | about 559 |",
    "| Employee_Number__c | Employee ID | Write when blank or different. Field length 10; HR max is 7. **Unique external Id**: where another contact (a surplus duplicate of the same person) already holds the HR number, the build skips the row and logs the holder Id; those go to the Phase 2 duplicate merge | about 559 |")
rep("3. Abort the build if any Id is missing, or if a record's Name does not contain the HR last name. This guards against a stale sandbox or the wrong org.",
    "3. Abort the build if any Id is missing, or if a record's Name does not carry the HR surname (normalised: '(On Leave)' stripped, apostrophes unified, hyphens ignored, whole-name equality or surname containment either way). This guards against a stale sandbox or the wrong org. Two Kam-maintained files refine it: `name_check_exceptions.csv` (Ids that fail the check but are the same person, matched on email; written) and `exclusions.csv` (Ids never written in any org). Both were approved 8 Sep 2026: six renamed people written, the Sentinel logadmin system user (matched to an employee on email alone) excluded.")
rep("GATE 2: stop. Kam reviews verify_sandbox.md.",
    "GATE 2: stop. Kam reviews verify_sandbox.md.\n\nFull UAT rehearsal, 8 Sep 2026: 13 + 7 Bulk jobs, 711 rows loaded, 0 failures after the uniqueness guard was added (2 DUPLICATE_VALUE failures on the first contact part led to the guard and a continuation build in out_FULLUAT/continue1/). verify_sandbox.md: 683 user fields, 75 manager fields and 879 contact fields match; 14 contact numbers skipped for duplicate holders; no baseline field moved; 0 Flow_Log__c entries in the window; second build zero changes; all 8 flags still false on the second read. Report and verify tooling in scripts/hr_sync_phase1/README.md.")
rep("5. Manager batch (`update_user_manager.csv`) only if D2 was cleared in Step 0.",
    "5. Manager batch (`update_user_manager.csv`) only if D2 was cleared in Step 0 and Kam has accepted the reporting effects listed in the dry run.\n6. EmployeeNumber and Employee_Code__c rows only after Finance has answered D6. If the answer is pending, run with `--batches contact,manager` and leave the user parts for a later run; the build is idempotent.")
rep("285 surplus duplicate contacts across 197 employees.",
    "285 surplus duplicate contacts across 197 employees, of which at least 14 hold the employee's HR number on the non-primary record (Employee_Number__c is unique, so the primary cannot take it until the merge).")
open(b, "w", encoding="utf-8", newline="\n").write(t)
print("brief v4 written")
