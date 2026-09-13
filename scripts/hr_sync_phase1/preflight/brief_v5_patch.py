"""Records Kam's D6 decision (answer 3, hold) in the brief as v5."""
b = r"C:\Users\Kamyar.Jannati\Downloads\Claude_Code_Brief_HR_to_Salesforce_Phase1.md"
t = open(b, encoding="utf-8").read()


def rep(o, n):
    global t
    assert t.count(o) == 1, o[:60]
    t = t.replace(o, n)


rep("Date: 8 September 2026 (v4, after the Full UAT rehearsal; v3 7 Sep after preflight; v2 7 Sep after review)",
    "Date: 8 September 2026 (v5, D6 hold decision; v4 same day after the Full UAT rehearsal; v3 7 Sep after preflight; v2 7 Sep after review)")
rep("| Ask Finance before Gate 1 whether the SUN import or commission process consumes that column. If yes, hold the EmployeeNumber write (and D1 mirror) until Finance has remapped, or first copy the legacy code to a field Finance agrees to use |",
    "| **Decided 8 Sep 2026 (Kam, answer 3, \"for now\"): hold.** User.EmployeeNumber and User.Employee_Code__c are not written in production until Finance confirms the SUN import and commission mapping can take the HR IDs. `build_changes.py` holds both by default (`--hold-fields`); release with `--hold-fields ''` on Finance's confirmation and run the user number rows as a later, idempotent load. Title, the manager batch and every Contact field still go. Contact.Employee_Number__c is unaffected (not on the SUN reports) |")
rep("6. EmployeeNumber and Employee_Code__c rows only after Finance has answered D6. If the answer is pending, run with `--batches contact,manager` and leave the user parts for a later run; the build is idempotent.",
    "6. EmployeeNumber and Employee_Code__c rows are HELD (D6, answer 3). The production build runs with the default hold, so the user batch carries Title only. When Finance confirms, rebuild with `--hold-fields ''`, review the dry run for the number rows alone, and load them as a separate run.")
open(b, "w", encoding="utf-8", newline="\n").write(t)
print("brief v5 written")
