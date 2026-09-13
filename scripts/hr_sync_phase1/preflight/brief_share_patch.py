"""Final consistency pass on the Workday team brief before Kam shares it."""
p = r"C:\Users\KAMYAR~1.JAN\AppData\Local\Temp\claude\C--sf-work-kjdev\26586c4b-037e-41a4-89d4-d6793f22b965\scratchpad\workday_user_field_brief.html"
s = open(p, encoding="utf-8").read()


def rep(o, n):
    global s
    assert s.count(o) == 1, o[:70]
    s = s.replace(o, n)


rep("the Phase 1 sync script writes the whole Workday block (Department, Division, Company Name and the seven new fields), only where the target org has the fields,",
    "the Phase 1 sync script writes the whole Workday block (Department, Company Name and the eight new fields; standard Division is never written), only where the target org has the fields,")
rep('<h4>Division</h4><p class="sub">standard Division · 9 allowed values</p>',
    '<h4>Workday Division</h4><p class="sub">Workday_Division__c · 9 values (standard Division is separate)</p>')
rep("The standard fields (Name, Title, Manager, Department, Division, Company Name, Employee Number) stay in the standard \"About\" block at the top of the page, where Salesforce fixes them;",
    "The standard fields (Name, Title, Manager, Department, Division, Company Name, Employee Number) stay in the standard \"About\" block at the top of the page, where Salesforce fixes them (Division there is the CRM business-unit value, which the sync does not touch);")
rep('<li>Production in two loads: fields and layout first (metadata, no data change), then the data run after its own dry run.</li>',
    '<li>Production, on Kam\'s GO PROD: fields and layout first (metadata, no data change), then the data run after its own production dry run. Employee Number and Employee Code stay held until Finance answers D6 from the Phase 1 brief.</li>')
rep('<span><b>Date</b> 8 Sep 2026</span>',
    '<span><b>Version</b> 3, 8 Sep 2026, after the Full UAT rehearsal</span>')
rep('<p class="eyebrow">Centellic CRM · Workday sync · User object</p>',
    '<p class="eyebrow">Centellic CRM · Workday sync · User object · for the CRM and Data team</p>')
# a short reader's guide after the header meta
rep('</header>\n\n<h2>1. The mapping</h2>',
    '</header>\n\n<div class="note"><p><b>How to read this.</b> Section 1 is the one-line answer per Workday column. Sections 2 to 4 are the detail behind the new fields. Section 5 is the page change. Section 7 is what we need from you: six open questions, each with a default we will take if nobody objects. Everything described is built and rehearsed in the sandboxes; nothing has changed in production.</p></div>\n\n<h2>1. The mapping</h2>')
rep('<h2>7. Open questions for the team</h2>',
    '<h2>7. Open questions for the team</h2>\n<p>Each has a default. Reply on the page or to Kam if you want a different answer; silence means the default stands when production is scheduled.</p>')
open(p, "w", encoding="utf-8").write(s)
print("brief share-ready")
