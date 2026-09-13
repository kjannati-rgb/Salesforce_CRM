"""Step 0 item 6 for any org: list Report/Dashboard/ListView metadata, retrieve it into preflight/reports_<org>/, and classify
every reference to the in-scope fields as display column vs filter/grouping. Usage: python reports_check.py PROD"""
import os, sys, json, subprocess, re, collections
import xml.etree.ElementTree as ET

ORG = sys.argv[1]
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "reports_%s" % ORG)
for v in ("HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy"):
    os.environ.pop(v, None)
NS = "{http://soap.sforce.com/2006/04/metadata}"

def q(soql):
    o = subprocess.run(["sf", "data", "query", "--target-org", ORG, "--query", soql, "--json"], capture_output=True, text=True, shell=True, encoding="utf-8").stdout
    return json.loads(o[o.find("{"):])["result"]["records"]

if not os.path.isdir(OUT) or not os.listdir(OUT):
    F = q("SELECT DeveloperName, Name, Type FROM Folder WHERE Type IN ('Report','Dashboard')")
    R = q("SELECT DeveloperName, FolderName FROM Report")
    D = q("SELECT DeveloperName, FolderName FROM Dashboard")
    L = q("SELECT DeveloperName, SobjectType FROM ListView WHERE SobjectType IN ('User','Contact','Lead','Opportunity','Case','Account')")
    byname = {(f["Type"], f["Name"]): f["DeveloperName"] for f in F if f["DeveloperName"]}
    members = collections.defaultdict(set); unres = collections.Counter()
    for r in R:
        dn = "unfiled$public" if r["FolderName"] == "Public Reports" else byname.get(("Report", r["FolderName"]))
        if dn: members["Report"].add("%s/%s" % (dn, r["DeveloperName"]))
        else: unres[r["FolderName"]] += 1
    for d in D:
        dn = byname.get(("Dashboard", d["FolderName"]))
        if dn: members["Dashboard"].add("%s/%s" % (dn, d["DeveloperName"]))
        else: unres["DB:" + str(d["FolderName"])] += 1
    for l in L: members["ListView"].add("%s.%s" % (l["SobjectType"], l["DeveloperName"]))
    print("listed: reports %d dashboards %d listviews %d | unresolved folders %s" % (len(R), len(D), len(L), dict(unres)), flush=True)
    xml = ['<?xml version="1.0" encoding="UTF-8"?>', '<Package xmlns="http://soap.sforce.com/2006/04/metadata">']
    for t, ns in members.items():
        xml.append("  <types>"); xml += ["    <members>%s</members>" % n for n in sorted(ns)]; xml.append("    <name>%s</name>" % t); xml.append("  </types>")
    xml.append("  <version>62.0</version></Package>")
    pkg = os.path.join(HERE, "package_reports_%s.xml" % ORG)
    open(pkg, "w", encoding="utf-8").write("\n".join(xml))
    os.makedirs(OUT, exist_ok=True)
    o = subprocess.run(["sf", "project", "retrieve", "start", "--target-org", ORG, "--manifest", pkg, "--output-dir", OUT, "--wait", "60", "--json"], capture_output=True, text=True, shell=True, encoding="utf-8").stdout
    j = json.loads(o[o.find("{"):]); r = j.get("result") or {}
    print("retrieve status %s files %d messages %d" % (j.get("status"), len(r.get("files", [])), len(r.get("messages") or [])), flush=True)

fields = {"User.EmployeeNumber": re.compile(r"EMPLOYEE_NUMBER|EmployeeNumber", re.I), "User.Employee_Code__c": re.compile(r"User\.Employee_Code__c", re.I),
          "User.Manager": re.compile(r"(USER|OWNER)S?\.MANAGER|\.Manager(Id)?\b|MANAGER_ID|Owner\.Manager|^MANAGER$", re.I),
          "Contact.Employee_Number__c": re.compile(r"Employee_Number__c", re.I), "Not_at_Company_Checkbox__c": re.compile(r"Not_at_Company_Checkbox__c", re.I),
          "No_Longer_w_Company__c": re.compile(r"No_Longer_w_Company__c", re.I), "ADvendio__LeftCompany__c": re.compile(r"ADvendio__LeftCompany__c", re.I),
          "User.Title": re.compile(r"USERS?\.TITLE|OWNER\.TITLE|USER\.Title|Owner\.Title|Owner:User\.Title", re.I),
          "Contact.Title": re.compile(r"^(CONTACT\.)?TITLE$|Contact\.Title$", re.I),
          "legacy EmployeeNumber code as filter value": None}
legacy = re.compile(r"^(A\d{3}|E\d{3}|G\d{3}|ALKF|APJK|H\d{3}|UCM)$", re.I)
res = {k: {"column": 0, "filter": []} for k in fields}
n = 0
for dp, _, fs in os.walk(OUT):
    for f in fs:
        p = os.path.join(dp, f); rel = os.path.relpath(p, OUT).replace("\\", "/")
        try: root = ET.parse(p).getroot()
        except Exception: continue
        kind = root.tag.replace(NS, ""); n += 1
        if kind == "Report":
            cols = [c.findtext(NS + "field") for c in root.iter(NS + "columns")]
            fl = [(c.findtext(NS + "column"), c.findtext(NS + "operator"), c.findtext(NS + "value")) for c in root.iter(NS + "criteriaItems")]
            gr = [g.findtext(NS + "field") for g in list(root.iter(NS + "groupingsDown")) + list(root.iter(NS + "groupingsAcross"))]
            rt = (root.findtext(NS + "reportType") or "").lower()
        elif kind == "ListView":
            cols = [c.text for c in root.iter(NS + "columns")]; fl = [(c.findtext(NS + "field"), c.findtext(NS + "operation"), c.findtext(NS + "value")) for c in root.iter(NS + "filters")]; gr = []; rt = "listview:" + rel.split("/")[1].lower() if rel.startswith("objects/") else "listview"
        elif kind == "Dashboard":
            cols = [c.text for c in root.iter(NS + "column")] + [c.text for c in root.iter(NS + "groupingColumn")]; fl = [(c.findtext(NS + "column"), None, None) for c in root.iter(NS + "dashboardFilterOptions")]; gr = []; rt = ""
        else: continue
        for k, rx in fields.items():
            if rx is None:
                for c, op, v in fl:
                    if v and any(legacy.match(x.strip()) for x in v.split(",")) and re.search(r"EMPLOYEE", c or "", re.I): res[k]["filter"].append((rel, c, op, v))
                continue
            def m(x): return x and rx.search(x)
            if k == "Contact.Title" and not (rt.startswith("contact") or rt.startswith("listview:contact") or "contact" in rt): continue
            fm = [x for x in fl if m(x[0])]; gm = [g for g in gr if m(g)]
            if fm or gm: res[k]["filter"].append((rel, [x for x in fm], gm))
            elif any(m(c) for c in cols): res[k]["column"] += 1
print("\nfiles parsed:", n)
for k, v in res.items():
    print("\n[%s] column-only %d | filter/grouping %d" % (k, v["column"], len(v["filter"])))
    for it in v["filter"][:12]: print("   ", it)
json.dump({k: {"column": v["column"], "filter": v["filter"]} for k, v in res.items()}, open(os.path.join(HERE, "report_hits_%s.json" % ORG), "w"), indent=1, default=str)
