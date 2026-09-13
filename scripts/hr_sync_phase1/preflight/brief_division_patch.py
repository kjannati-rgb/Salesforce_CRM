"""Rewrites the Division section of the Workday team brief (artifact HTML) after the usage check, and updates the memory note."""
p = r"C:\Users\KAMYAR~1.JAN\AppData\Local\Temp\claude\C--sf-work-kjdev\26586c4b-037e-41a4-89d4-d6793f22b965\scratchpad\workday_user_field_brief.html"
s = open(p, encoding="utf-8").read()


def rep(o, n):
    global s
    assert s.count(o) == 1, o[:60]
    s = s.replace(o, n)


rep('<tr><td>Division</td><td>Division</td><td class="mono">Division</td><td>Standard Text(80), value-checked</td><td><span class="chip keep">Existing</span> <span class="chip warn">see §3</span></td></tr>',
    '<tr><td>Division</td><td>Workday Division</td><td class="mono">Workday_Division__c</td><td>Picklist, 9 values</td><td><span class="chip new">New field</span> <span class="chip warn">see §3</span></td></tr>')
rep('five existing fields keep receiving values, seven fields are new,', 'four existing fields keep receiving values, eight fields are new,')
rep('<tr><td class="mono">Workday_Last_Sync__c</td><td>Date/Time</td>',
    '<tr><td class="mono">Workday_Division__c</td><td>Picklist, restricted, 9 values</td><td>Workday Division verbatim. Deliberately separate from the standard Division field; see §3.</td></tr>\n<tr><td class="mono">Workday_Last_Sync__c</td><td>Date/Time</td>')
rep('<p style="margin-top:14px">All seven new fields are read-only', '<p style="margin-top:14px">All eight new fields are read-only')

i = s.index('<h2>3. Division: can it become a picklist?</h2>')
j = s.index('<div class="note warn">')
new3 = """<h2>3. Division: can it become a picklist?</h2>
<p>Not the standard one, and it turns out we should not write Workday's value into it at all. <code>Division</code> on User is a standard text field, so its type cannot change. More importantly, it is not empty or idle: production holds a CRM business-unit taxonomy in it today (Market Intelligence 107 users, Practice Intelligence 92, Events 82, ALM Legal - Info Services 79, Operations 51, MBL Seminars 15, and a long tail), and that taxonomy is what the org depends on.</p>
<p>Where the standard Division is used, from the production report retrieve and the repo:</p>
<ul>
<li><b>57 reports, dashboards and list views filter or group on it</b>, by value: "Legal Information" (14 reports), "events, benchmarking, legal information, legal careers group" (12), "Market Intelligence" (3), "Legal Careers Group" (3), "Benchmarking" (2), plus the whole Pipeline Tracker dashboard, which groups every chart by owner division. Another 45 show it as a column.</li>
<li><b>ChurnZero segmentation.</b> <code>Opportunity_Owner_Division__c</code> is a formula that reads the owner's Division and is sent to ChurnZero for division-level segmentation of opportunities.</li>
<li>A draft flow (Update Opp Stage to Evaluation) branches on Division = Events or MBL Seminars.</li>
</ul>
<p>Workday's nine divisions (Commercial, Content and Editorial, Product &amp; Technology, Operations Finance...) are a different cut of the business. Writing them into the standard field would empty 57 report filters overnight and change what ChurnZero receives. So:</p>
<ol>
<li><b>Workday Division becomes its own restricted picklist, <code>Workday_Division__c</code>, nine values.</b> The sync writes it; nothing else reads it yet.</li>
<li><b>Standard Division is left exactly as it is</b>, maintained by the CRM team as today, and stays outside the sync.</li>
<li>Whether the two taxonomies should converge is a separate decision for the team, taken with the report owners and ChurnZero in the room (open question 6). The validation rule that would police standard Division against the Workday values exists but is deployed inactive, ready if that decision is ever "converge".</li>
</ol>
<p><code>Department</code> (113 distinct Workday values, up to 49 characters) and <code>CompanyName</code> have no filter consumers in the report retrieve and are written as standard text.</p>
"""
s = s[:i] + new3 + s[j:]

rep('<li class="new">Hire Date</li><li class="mv">Title</li><li class="new">Employee Type</li><li class="mv">Department</li><li class="mv">Division</li><li class="new">Sub Division</li>',
    '<li class="new">Hire Date</li><li class="mv">Title</li><li class="new">Employee Type</li><li class="mv">Department</li><li class="new">Workday Division</li><li class="new">Sub Division</li>')
rep('<td>Workday Employee ID, Hire Date, Title, Employee Type, Department, Sub Division, Division, Location, Manager, ELT Lead, Company Name, Workday Last Sync. Employee Number and Employee Code follow later, once Finance releases D6.</td>',
    '<td>Workday Employee ID, Hire Date, Title, Employee Type, Department, Workday Division, Sub Division, Location, Manager, ELT Lead, Company Name, Workday Last Sync. Employee Number and Employee Code follow later, once Finance releases D6.</td>')
rep('<td>Name, Email, Username, Active, Profile, Role, permission sets, Team, Team Role, Price Book,',
    '<td>Name, Email, Username, Active, Profile, Role, permission sets, <b>standard Division</b> (CRM business-unit taxonomy, see §3), Team, Team Role, Price Book,')
rep('<li><b>Who may edit the Workday block by hand.</b> Proposal: nobody but System Administrators, and only to fix a sync fault. Confirm.</li>',
    '<li><b>Who may edit the Workday block by hand.</b> Proposal: nobody but System Administrators, and only to fix a sync fault. Confirm.</li>\n<li><b>Two division taxonomies.</b> Standard Division (CRM business units, 57 report filters, ChurnZero) and Workday Division (nine Workday values) now sit side by side. Keep both indefinitely, or plan a convergence with the report owners? No sync change is needed either way.</li>')
rep('<li><b>Done 8 Sep in KJDEV:</b> seven fields, the Division validation rule (bypass via Application Settings), the User layout regrouped',
    '<li><b>Done 8 Sep in KJDEV:</b> eight fields (Workday Division added after the usage check in §3), the Division validation rule deployed inactive, the User layout regrouped')
rep('Smoke-tested in KJDEV: 418 user rows loaded in 17 Bulk jobs, 0 failures, 3,588 field values verified, no side effects, second build zero changes.',
    'Smoke-tested in KJDEV: 418 user rows loaded in 17 Bulk jobs, then 357 rows for Workday Division, 0 failures, no side effects, second build zero changes. The standard Division values the first smoke run touched were restored from the backup.')
open(p, "w", encoding="utf-8").write(s)
print("brief html patched")

m = r"C:\Users\Kamyar.Jannati\.claude\projects\C--sf-work-kjdev\memory\project_hr-to-salesforce-employee-sync.md"
t = open(m, encoding="utf-8").read()
old = "Standard Division cannot become a picklist (Opportunity_Owner_Division__c formula depends on it)."
assert t.count(old) == 1
t = t.replace(old, "STANDARD DIVISION IS NOT WRITTEN: it holds the CRM business-unit taxonomy (Market Intelligence/Practice Intelligence/Events/ALM Legal.../MBL Seminars) used by 57 report filters+groupings (Pipeline Tracker dashboard, Legal Information/LCG/Benchmarking sales reports), the ChurnZero formula Opportunity_Owner_Division__c and a draft flow; Workday's 9 divisions are a different taxonomy -> new restricted picklist Workday_Division__c (8th field). VR Division_Workday_Values deployed INACTIVE. KJDEV smoke run had overwritten Division on 350 users; restored from backup 8 Sep.")
open(m, "w", encoding="utf-8").write(t)
print("memory updated")
