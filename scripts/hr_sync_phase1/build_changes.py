"""HR to Salesforce employee sync, Phase 1 - Step 1: build the change set. NO DML.

Usage:
  python build_changes.py --org FULLUAT
  python build_changes.py --org PROD

Reads the HR extract and the Id mapping workbook, queries the current values from the target org,
and writes to out_<org>/:
  changes_user.csv, changes_user_manager.csv, changes_contact.csv   (Id, <field>_old, <field>_new ...; rows with a real change only)
  update_user.csv, update_user_manager.csv, update_contact.csv       (Id + new-value columns, Bulk API shape) + parts/ split at 200 rows
  backup_<orgId>_<ts>_<object>.csv                                   (Id + current values of every in-scope and baseline field, all found records)
  rollback_<object>.csv                                              (Id + old values for the changed rows, Bulk API shape)
  dry_run_report.md
Deterministic and idempotent: a second run against an updated org produces zero changes.
"""
import argparse, csv, json, os, re, subprocess, sys, collections, datetime
import xml.etree.ElementTree as ET
import openpyxl
from openpyxl.utils import column_index_from_string as ci

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_HR = r"C:\Users\Kamyar.Jannati\Downloads\Current_Employee_List_non_confidential_7.9.26.xlsx"
DEFAULT_MAP = r"C:\Users\Kamyar.Jannati\Downloads\Centellic_Employee_to_Salesforce_Mapping_2026-09-07.xlsx"
PROD_ORG_ID = "00D6g0000081IOg"
SANDBOX_ALIASES = {"FULLUAT", "KJDEV"}
ON_LEAVE = re.compile(r"\s*\((On Leave|on leave)\)\s*$")

USER_FIELDS = ["Title", "EmployeeNumber", "Employee_Code__c", "ManagerId"]
# Workday extension (team brief, 8 Sep 2026). Standard fields are always present; the custom ones are written only where the
# target org has them (KJDEV first, then Full UAT / production after the metadata deploys).
WORKDAY_STD_FIELDS = ["Department", "CompanyName"]
# Standard Division is NOT written: it carries the CRM business-unit taxonomy (57 report filters/groupings, ChurnZero
# segmentation formula Opportunity_Owner_Division__c). Workday's division goes to Workday_Division__c.
WORKDAY_CUSTOM_FIELDS = ["Workday_Employee_ID__c", "Hire_Date__c", "Workday_Division__c", "Sub_Division__c", "Location__c", "Employee_Type__c", "ELT_Lead__c", "Workday_Last_Sync__c"]
WORKDAY_PICKLISTS = {"Workday_Division__c", "Sub_Division__c", "Location__c", "Employee_Type__c"}
DIVISION_VALUES = ["Commercial", "Content and Editorial", "Product & Technology", "Operations Finance", "Corporate Strategy", "Operations",
                   "Operations People & Culture", "Corporate Executive", "Executive Office"]
USER_BASELINE = ["Name", "LastName", "Email", "IsActive", "Manager_Email__c", "Manager.Name", "Manager.Email", "SystemModstamp", "LastModifiedById"]
CONTACT_FIELDS = ["Employee_Number__c", "Title", "Not_at_Company_Checkbox__c", "No_Longer_w_Company__c", "ADvendio__LeftCompany__c"]
CONTACT_BASELINE = ["Name", "LastName", "Email", "AccountId", "Account.Name", "LID__No_longer_at_Company__c", "DoNotCall", "HasOptedOutOfEmail",
                    "No_Postal__c", "ReportsToId", "SystemModstamp", "LastModifiedById"]

for v in ("HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy"):
    os.environ.pop(v, None)


# ---------- comparison rules (shared with verify; see brief Step 1.6) ----------
def norm_title(x):
    return (x or "").strip().casefold()

def same_title(a, b):
    return norm_title(a) == norm_title(b)

def same_exact(a, b):
    return (a or "") == (b or "")

def id18(x):
    return (x or "").strip()[:18] if x else ""


# ---------- org access ----------
def sf_json(args):
    o = subprocess.run(["sf"] + args + ["--json"], capture_output=True, text=True, shell=True, encoding="utf-8")
    txt = o.stdout
    i = txt.find("{")
    if i < 0:
        raise RuntimeError("sf returned no JSON: " + (o.stderr or txt)[:500])
    j = json.loads(txt[i:])
    if j.get("status") != 0:
        raise RuntimeError("sf error: " + json.dumps(j)[:1500])
    return j["result"]

def org_display(alias):
    r = sf_json(["org", "display", "--target-org", alias])
    return {"orgId": r["id"], "username": r["username"], "instance": r.get("instanceUrl"), "alias": alias}

def query(alias, soql):
    return sf_json(["data", "query", "--target-org", alias, "--query", soql])["records"]

def flat(rec, path):
    cur = rec
    for part in path.split("."):
        if cur is None:
            return None
        cur = cur.get(part)
    return cur

def fetch_by_ids(alias, obj, ids, fields):
    out = {}
    ids = sorted(ids)
    for i in range(0, len(ids), 200):
        soql = "SELECT Id,%s FROM %s WHERE Id IN (%s)" % (",".join(fields), obj, ",".join("'%s'" % x for x in ids[i:i + 200]))
        for r in query(alias, soql):
            out[id18(r["Id"])] = {f: flat(r, f) for f in fields} | {"Id": id18(r["Id"])}
    return out


# ---------- inputs ----------
def load_hr(path):
    ws = openpyxl.load_workbook(path, read_only=True, data_only=True)["Sheet1"]
    rows = list(ws.iter_rows(min_row=2, values_only=True))
    hdr = [str(x).strip() if x is not None else "" for x in rows[0]]
    col = {h: i for i, h in enumerate(hdr)}
    hr = {}
    for r in rows[1:]:
        if r[col["Employee ID"]] is None:
            continue
        emp = str(r[col["Employee ID"]]).strip()
        hr[emp] = {
            "emp": emp,
            "worker": (r[col["Worker"]] or "").strip(),
            "pref": (r[col["Preferred Name"]] or "").strip(),
            "title": (r[col["Business Title"]] or "").strip() if r[col["Business Title"]] else "",
            "manager": (r[col["Worker's Manager"]] or "").strip() if r[col["Worker's Manager"]] else "",
            "email": (r[col["Email - Work"]] or "").strip() if r[col["Email - Work"]] else "",
            "raw_emp_type": type(r[col["Employee ID"]]).__name__,
            # Workday extension columns
            "hire_date": r[col["Hire Date"]].strftime("%Y-%m-%d") if hasattr(r[col["Hire Date"]], "strftime") else (str(r[col["Hire Date"]]).strip()[:10] if r[col["Hire Date"]] else ""),
            "department": (str(r[col["Department"]]).strip() if r[col["Department"]] else ""),
            "sub_division": (str(r[col["Sub Division"]]).strip() if r[col["Sub Division"]] else ""),
            "division": (str(r[col["Division"]]).strip() if r[col["Division"]] else ""),
            "elt": (str(r[col["ELT Lead"]]).strip() if r[col["ELT Lead"]] else ""),
            "location": (str(r[col["Location - Name"]]).strip() if r[col["Location - Name"]] else ""),
            "company": (str(r[col["Company"]]).strip() if r[col["Company"]] else ""),
            "emp_type": (str(r[col["Employee Type"]]).strip() if r[col["Employee Type"]] else ""),
        }
    return hr


def describe_user(alias):
    """Field presence and active picklist values on User in the target org."""
    r = sf_json(["sobject", "describe", "--sobject", "User", "--target-org", alias])
    present = {f["name"] for f in r["fields"]}
    picks = {f["name"]: {p["value"] for p in f.get("picklistValues", []) if p.get("active", True)} for f in r["fields"] if f["type"] == "picklist"}
    return present, picks

def load_mapping(path):
    wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
    e = list(wb["Employees"].iter_rows(values_only=True))
    c = lambda L: ci(L) - 1
    assert e[0][c("A")] == "Employee ID" and e[0][c("AD")] == "Primary User Id" and e[0][c("AE")] == "Primary User active" and e[0][c("AF")] == "Primary Contact Id", "Employees sheet layout changed"
    emp = {}
    for r in e[1:]:
        if not r[c("A")]:
            continue
        emp[str(r[c("A")]).strip()] = {"user": id18(r[c("AD")]) if r[c("AD")] else "", "user_active": str(r[c("AE")] or "").strip().lower() == "yes",
                                       "contact": id18(r[c("AF")]) if r[c("AF")] else "", "pref": (r[c("C")] or "").strip()}
    u = list(wb["Users"].iter_rows(values_only=True))
    assert u[0][c("K")] == "Match tier" and u[0][c("N")] == "User Id", "Users sheet layout changed"
    confirmed = {id18(r[c("N")]) for r in u[1:] if r[c("N")] and str(r[c("K")] or "").strip().lower() == "confirmed"}
    return emp, confirmed


# ---------- report predicates (from the Step 0 metadata retrieve, if present) ----------
NS = "{http://soap.sforce.com/2006/04/metadata}"

def load_predicates(meta_dir):
    """Returns {'user_title': [...], 'manager': [...], 'contact_title': [...]} of (source, column, operator, value)."""
    preds = {"user_title": [], "manager": [], "contact_title": []}
    if not meta_dir or not os.path.isdir(meta_dir):
        return preds
    for dp, _, fs in os.walk(meta_dir):
        for f in fs:
            p = os.path.join(dp, f)
            try:
                root = ET.parse(p).getroot()
            except Exception:
                continue
            kind = root.tag.replace(NS, "")
            src = os.path.relpath(p, meta_dir).replace("\\", "/")
            if kind == "Report":
                rt = (root.findtext(NS + "reportType") or "").lower()
                items = [(c.findtext(NS + "column"), c.findtext(NS + "operator"), c.findtext(NS + "value")) for c in root.iter(NS + "criteriaItems")]
            elif kind == "ListView":
                rt = "listview:" + src.split("/")[1].lower() if src.startswith("objects/") else "listview"
                items = [(c.findtext(NS + "field"), c.findtext(NS + "operation"), c.findtext(NS + "value")) for c in root.iter(NS + "filters")]
            else:
                continue
            for colname, op, val in items:
                if not colname:
                    continue
                cu = colname.upper()
                if re.search(r"OWNER\.TITLE|USERS?\.TITLE|USER\.TITLE", cu):
                    preds["user_title"].append((src, colname, op, val))
                elif re.search(r"OWNER_MANAGER|OWNER\.MANAGER|USER\$MANAGER|^MANAGER$|CORE\.USERS\.MANAGER", cu):
                    preds["manager"].append((src, colname, op, val))
                elif cu in ("TITLE", "CONTACT.TITLE") and (rt.startswith("contact") or rt.startswith("listview:contact") or rt.startswith("campaign") or "contact" in rt):
                    preds["contact_title"].append((src, colname, op, val))
    return preds

def eval_pred(op, val, text):
    """Salesforce report/list-view filter semantics, simplified: comma-separated value lists, case-insensitive."""
    t = (text or "").casefold()
    vals = [v.strip().strip("'\"").casefold() for v in (val or "").split(",")]
    vals = [v for v in vals if v != ""] or [""]
    if op in ("contains",):
        return any(v and v in t for v in vals)
    if op in ("notContain",):
        return not any(v and v in t for v in vals)
    if op in ("equals",):
        return t in vals
    if op in ("notEqual",):
        return t not in vals
    if op in ("startsWith",):
        return any(t.startswith(v) for v in vals)
    return None


# ---------- main ----------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--org", required=True)
    ap.add_argument("--hr", default=DEFAULT_HR)
    ap.add_argument("--mapping", default=DEFAULT_MAP)
    ap.add_argument("--meta-dir", default=None, help="retrieved report/listview metadata for the filter-membership diff (default preflight/reports_<org>)")
    ap.add_argument("--out", default=None)
    ap.add_argument("--hold-fields", default="EmployeeNumber,Employee_Code__c",
                    help="User fields NOT written until Finance answers D6 (Kam, 8 Sep 2026: answer 3, hold). Pass '' to release.")
    ap.add_argument("--users-only", action="store_true", help="skip Contact entirely (KJDEV smoke tests: no contact data, drifted Contact fields)")
    ap.add_argument("--no-workday", action="store_true", help="Phase 1 scope only: do not write Department, CompanyName or the Workday custom fields")
    ap.add_argument("--allow-inactive-managers", action="store_true",
                    help="write ManagerId / ELT_Lead__c even when the target user is inactive (the API accepts it; the org's IsActive is used, not the mapping's column)")
    a = ap.parse_args()
    hold = {f.strip() for f in a.hold_fields.split(",") if f.strip()}
    alias = a.org
    is_sandbox = alias.upper() in SANDBOX_ALIASES
    out = a.out or os.path.join(HERE, "out_%s" % alias)
    os.makedirs(os.path.join(out, "parts"), exist_ok=True)
    meta_dir = a.meta_dir or os.path.join(HERE, "preflight", "reports_%s" % alias)
    ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    log = []
    def say(*x):
        s = " ".join(str(i) for i in x); print(s); log.append(s)

    # 1. org verification (protocol 1)
    org = org_display(alias)
    say("Org:", org["alias"], org["orgId"], org["username"], org["instance"])
    if not is_sandbox and not org["orgId"].startswith(PROD_ORG_ID):
        sys.exit("ABORT: alias %s is not a sandbox and its Org Id %s is not production %s" % (alias, org["orgId"], PROD_ORG_ID))
    if is_sandbox and org["orgId"].startswith(PROD_ORG_ID):
        sys.exit("ABORT: alias %s resolved to the production org" % alias)

    # 2. inputs
    hr = load_hr(a.hr)
    emp, confirmed = load_mapping(a.mapping)
    by_pref = {v["pref"]: v for v in hr.values()}
    assert len(by_pref) == len(hr), "Preferred Name is not unique in the HR extract"
    say("HR rows:", len(hr), "| mapping employees:", len(emp), "| confirmed users:", len(confirmed))
    lead_zero = sum(1 for k in hr if k.startswith("0"))
    non_str = sum(1 for v in hr.values() if v["raw_emp_type"] != "str")
    say("Employee IDs with leading zero:", lead_zero, "| non-text Employee ID cells:", non_str)

    in_users = {}      # userId -> emp
    in_contacts = {}   # contactId -> emp
    for e, m in emp.items():
        if e not in hr:
            continue
        if m["user"] and m["user_active"] and m["user"] in confirmed:
            in_users[m["user"]] = e
        if m["contact"]:
            in_contacts[m["contact"]] = e
    # Kam-approved exclusions (exclusions.csv): Ids never written in any org
    excl_path = os.path.join(HERE, "exclusions.csv")
    excluded = {}
    if os.path.exists(excl_path):
        with open(excl_path, encoding="utf-8") as f:
            excluded = {id18(r["Id"]): r.get("Reason", "") for r in csv.DictReader(f)}
    if a.users_only:
        in_contacts = {}
    excluded_hits = [(k, in_users.pop(k)) for k in list(in_users) if k in excluded] + [(k, in_contacts.pop(k)) for k in list(in_contacts) if k in excluded]
    say("In scope: users", len(in_users), "(brief expects 412) | contacts", len(in_contacts), "(brief expects 744) | excluded by exclusions.csv:", len(excluded_hits))

    # manager resolution: HR manager name -> HR employee -> mapping primary user (active = Yes)
    stripped = [0]
    def resolve_person(name, role):
        """HR name -> HR employee (exact Preferred Name, then with '(On Leave)' stripped) -> mapping primary user, active = Yes."""
        if not name:
            return None, "%s blank in HR" % role
        row = by_pref.get(name)
        if row is None and ON_LEAVE.search(name):
            row = by_pref.get(ON_LEAVE.sub("", name)); stripped[0] += 1 if row else 0
        if row is None:
            return None, "%s '%s' not found in HR by Preferred Name" % (role, name)
        mm = emp.get(row["emp"])
        if not mm or not mm["user"]:
            return None, "%s '%s' has no primary user in the mapping" % (role, name)
        if not mm["user_active"] and not a.allow_inactive_managers:
            return None, "%s '%s' primary user is inactive" % (role, name)
        return mm["user"], ""
    mgr_user, mgr_reason, elt_user, elt_reason = {}, {}, {}, {}
    for e, h in hr.items():
        mgr_user[e], mgr_reason[e] = resolve_person(h["manager"], "manager")
        elt_user[e], elt_reason[e] = resolve_person(h["elt"], "ELT lead")
    stripped = stripped[0]
    say("Manager/ELT names resolved after stripping '(On Leave)':", stripped)

    # 3. current org values (+ baseline). Workday custom fields are included only where the org has them.
    present, org_picks = describe_user(alias)
    wd_present = [] if a.no_workday else [f for f in WORKDAY_CUSTOM_FIELDS if f in present]
    wd_missing = [f for f in WORKDAY_CUSTOM_FIELDS if f not in present]
    wd_std = [] if a.no_workday else WORKDAY_STD_FIELDS
    user_fields = USER_FIELDS + wd_std + wd_present
    if a.no_workday: say("Workday extension OFF (--no-workday): Phase 1 fields only")
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
    say("Workday custom fields in %s: %d of %d present; missing: %s" % (alias, len(wd_present), len(WORKDAY_CUSTOM_FIELDS), wd_missing or "none"))
    users = fetch_by_ids(alias, "User", in_users.keys(), user_fields + USER_BASELINE)
    contacts = fetch_by_ids(alias, "Contact", in_contacts.keys(), CONTACT_FIELDS + CONTACT_BASELINE)
    all_users = {id18(r["Id"]): r for r in query(alias, "SELECT Id, Name, ManagerId, IsActive, Email FROM User")}
    say("Found in %s: users %d/%d, contacts %d/%d" % (alias, len(users), len(in_users), len(contacts), len(in_contacts)))

    skips = collections.defaultdict(list)   # reason -> [(obj, id, name)]
    missing_u = [u for u in in_users if u not in users]
    missing_c = [c for c in in_contacts if c not in contacts]
    inactive_u = [u for u, r in users.items() if not r["IsActive"]]
    if (missing_u or missing_c) and not is_sandbox:
        sys.exit("ABORT: %d user and %d contact Ids from the mapping do not exist in %s" % (len(missing_u), len(missing_c), alias))
    for u in missing_u: skips["Id missing in target org (sandbox exception: skipped)"].append(("User", u, hr[in_users[u]]["pref"]))
    for c in missing_c: skips["Id missing in target org (sandbox exception: skipped)"].append(("Contact", c, hr[in_contacts[c]]["pref"]))
    for u in inactive_u: skips["User inactive in target org although mapping says active (skipped)"].append(("User", u, users[u]["Name"]))
    for k, e in excluded_hits: skips["Excluded by exclusions.csv (Kam-approved, never written)"].append(("User" if k.startswith("005") else "Contact", k, "%s: %s" % (hr[e]["pref"], excluded[k])))

    # name check: the org record must carry the HR surname. Normalised: '(On Leave)' stripped, curly/straight apostrophes
    # unified, hyphens/spaces ignored; passes when the HR last token is inside the org Name OR the org LastName is inside
    # the HR Worker name (covers double-barrelled and multi-part surnames on either side). Remaining failures: production
    # aborts unless the Id is listed in name_check_exceptions.csv (Kam-approved at Gate 1); a sandbox logs and skips them.
    def nrm(x):
        x = ON_LEAVE.sub("", x or "")
        return re.sub(r"[\s\-]", "", x.replace("’", "'").replace("‘", "'")).casefold()
    def name_ok(org_name, org_last, worker):
        if nrm(worker) == nrm(org_name):
            return True                      # whole name identical (covers two-letter surnames such as So, Yu, Ng, Lo)
        last = nrm(ON_LEAVE.sub("", worker).split()[-1])
        return (len(last) >= 3 and last in nrm(org_name)) or (len(nrm(org_last)) >= 3 and nrm(org_last) in nrm(worker))
    exc_path = os.path.join(HERE, "name_check_exceptions.csv")
    exceptions = {}
    if os.path.exists(exc_path):
        with open(exc_path, encoding="utf-8") as f:
            exceptions = {id18(r["Id"]): r for r in csv.DictReader(f)}
    bad = []
    for u, r in users.items():
        if not name_ok(r["Name"], r["LastName"], hr[in_users[u]]["worker"]): bad.append(("User", u, r["Name"], hr[in_users[u]]["worker"]))
    for c, r in contacts.items():
        if not name_ok(r["Name"], r["LastName"], hr[in_contacts[c]]["worker"]): bad.append(("Contact", c, r["Name"], hr[in_contacts[c]]["worker"]))
    excused = [b for b in bad if b[1] in exceptions]
    bad = [b for b in bad if b[1] not in exceptions]
    for b in bad: say("NAME CHECK FAILED:", b)
    if bad and not is_sandbox:
        sys.exit("ABORT: %d records whose Name does not carry the HR surname and are not in name_check_exceptions.csv" % len(bad))
    for obj, rid, oname, worker in bad:
        skips["Name check failed (sandbox exception: skipped; org name vs HR name)"].append((obj, rid, "%s vs HR %s" % (oname, worker)))
        (users if obj == "User" else contacts).pop(rid)
    for obj, rid, oname, worker in excused:
        skips["Name check excused by name_check_exceptions.csv (written)"].append((obj, rid, "%s vs HR %s" % (oname, worker)))
    say("Name check: %d users and %d contacts pass; %d skipped; %d excused" % (len(users), len(contacts), len(bad), len(excused)))

    # 4. diffs
    u_changes, m_changes, c_changes = [], [], []
    counts = collections.Counter()
    mgr_skips = []
    for u, r in users.items():
        if not r["IsActive"]:
            continue
        h = hr[in_users[u]]
        row = {"Id": u, "Name": r["Name"]}
        chg = False
        # Title
        if h["title"]:
            if not same_title(r["Title"], h["title"]):
                row["Title_old"], row["Title_new"] = r["Title"] or "", h["title"]; counts["User.Title"] += 1; chg = True
            else: counts["User.Title equal"] += 1
        else: counts["User.Title blank in HR (skipped)"] += 1
        # EmployeeNumber (exact string) and Employee_Code__c (D1 mirror); both held while D6 is open
        if h["emp"]:
            for f in ("EmployeeNumber", "Employee_Code__c"):
                if same_exact(r[f], h["emp"]):
                    counts["User.%s equal" % f] += 1
                elif f in hold:
                    counts["User.%s held (D6)" % f] += 1
                else:
                    row[f + "_old"], row[f + "_new"] = r[f] or "", h["emp"]; counts["User.%s" % f] += 1; chg = True
        # Workday extension: standard text fields (trimmed, case-insensitive compare), Division restricted to the nine values
        for f, key in (("Department", "department"), ("CompanyName", "company")):
            if f not in wd_std: continue
            if not h[key]: counts["User.%s blank in HR (skipped)" % f] += 1
            elif same_title(r.get(f), h[key]): counts["User.%s equal" % f] += 1
            else: row[f + "_old"], row[f + "_new"] = r.get(f) or "", h[key]; counts["User.%s" % f] += 1; chg = True
        # Workday custom fields, only where the org has them (Workday_Division__c replaces the standard Division write)
        wd_plain = {"Workday_Employee_ID__c": h["emp"], "Hire_Date__c": h["hire_date"], "Workday_Division__c": h["division"], "Sub_Division__c": h["sub_division"], "Location__c": h["location"], "Employee_Type__c": h["emp_type"]}
        for f, val in wd_plain.items():
            if f not in wd_present: continue
            if not val: counts["User.%s blank in HR (skipped)" % f] += 1; continue
            if f in WORKDAY_PICKLISTS and val not in org_picks.get(f, set()):
                skips["User.%s value not in the org picklist (skipped; add the value first)" % f].append(("User", u, "%s: %s" % (r["Name"], val))); counts["User.%s skipped (picklist)" % f] += 1; continue
            cur = r.get(f); cur = cur[:10] if (f == "Hire_Date__c" and cur) else cur
            if same_exact(cur, val): counts["User.%s equal" % f] += 1
            else: row[f + "_old"], row[f + "_new"] = cur or "", val; counts["User.%s" % f] += 1; chg = True
        if "ELT_Lead__c" in wd_present:
            target = elt_user.get(in_users[u])
            if target is None:
                skips["User.ELT_Lead__c unresolved (skipped)"].append(("User", u, "%s: %s" % (r["Name"], elt_reason[in_users[u]]))); counts["User.ELT_Lead__c skipped (unresolved)"] += 1
            elif target not in all_users:
                skips["User.ELT_Lead__c unresolved (skipped)"].append(("User", u, "%s: ELT user %s not in target org" % (r["Name"], target))); counts["User.ELT_Lead__c skipped (unresolved)"] += 1
            elif id18(r.get("ELT_Lead__c")) != target:
                row["ELT_Lead__c_old"], row["ELT_Lead__c_new"] = id18(r.get("ELT_Lead__c")), target; row["ELT_Lead_name_new"] = all_users[target]["Name"]; counts["User.ELT_Lead__c"] += 1; chg = True
            else: counts["User.ELT_Lead__c equal"] += 1
        if chg and "Workday_Last_Sync__c" in wd_present:
            row["Workday_Last_Sync__c_old"], row["Workday_Last_Sync__c_new"] = r.get("Workday_Last_Sync__c") or "", stamp
        if chg: u_changes.append(row)
        # ManagerId (separate batch, D2)
        target = mgr_user.get(in_users[u])
        if target is None:
            mgr_skips.append((u, r["Name"], mgr_reason[in_users[u]])); counts["User.ManagerId skipped (unresolved)"] += 1
        elif target not in all_users:
            mgr_skips.append((u, r["Name"], "manager user %s not in target org" % target)); counts["User.ManagerId skipped (manager Id missing in org)"] += 1
        elif not all_users[target]["IsActive"] and not a.allow_inactive_managers:
            mgr_skips.append((u, r["Name"], "manager user %s inactive in target org" % all_users[target]["Name"])); counts["User.ManagerId skipped (manager inactive in org)"] += 1
        elif id18(r["ManagerId"]) != target:
            if not all_users[target]["IsActive"]: counts["User.ManagerId written to an INACTIVE manager (allowed by flag)"] += 1
            mrow = {"Id": u, "Name": r["Name"], "ManagerId_old": id18(r["ManagerId"]), "ManagerId_new": target,
                    "Manager_old": r["Manager.Name"] or "", "Manager_new": all_users[target]["Name"], "Manager_new_active": "yes" if all_users[target]["IsActive"] else "NO",
                    "Manager_Email__c_old": r["Manager_Email__c"] or "", "Manager_Email__c_expected": all_users[target]["Email"] or ""}
            if "Workday_Last_Sync__c" in wd_present:
                mrow["Workday_Last_Sync__c_old"], mrow["Workday_Last_Sync__c_new"] = r.get("Workday_Last_Sync__c") or "", stamp
            m_changes.append(mrow)
            counts["User.ManagerId"] += 1
        else: counts["User.ManagerId equal"] += 1

    for c, r in contacts.items():
        h = hr[in_contacts[c]]
        row = {"Id": c, "Name": r["Name"]}
        chg = False
        if h["emp"] and not same_exact(r["Employee_Number__c"], h["emp"]):
            row["Employee_Number__c_old"], row["Employee_Number__c_new"] = r["Employee_Number__c"] or "", h["emp"]; counts["Contact.Employee_Number__c"] += 1; chg = True
        elif h["emp"]: counts["Contact.Employee_Number__c equal"] += 1
        if h["title"]:
            if not same_title(r["Title"], h["title"]):
                row["Title_old"], row["Title_new"] = r["Title"] or "", h["title"]; counts["Contact.Title"] += 1; chg = True
            else: counts["Contact.Title equal"] += 1
        else: counts["Contact.Title blank in HR (skipped)"] += 1
        for f in ("Not_at_Company_Checkbox__c", "No_Longer_w_Company__c", "ADvendio__LeftCompany__c"):
            if r[f]:
                row[f + "_old"], row[f + "_new"] = "true", "false"; counts["Contact." + f] += 1; chg = True
        if chg: c_changes.append(row)

    # Contact.Employee_Number__c is UNIQUE (external Id). Skip the write where another contact already holds the HR number
    # (a surplus duplicate of the same person, Phase 2 merge item); log the holder so Kam can see it.
    wanted = {r["Employee_Number__c_new"]: r for r in c_changes if "Employee_Number__c_new" in r}
    holders = {}
    wl = sorted(wanted)
    for i in range(0, len(wl), 200):
        for h in query(alias, "SELECT Id, Name, Email, Employee_Number__c FROM Contact WHERE Employee_Number__c IN (%s)" % ",".join("'%s'" % x.replace("'", "\\'") for x in wl[i:i + 200])):
            holders.setdefault(h["Employee_Number__c"], []).append(h)
    for num, row in wanted.items():
        others = [h for h in holders.get(num, []) if id18(h["Id"]) != row["Id"]]
        if others:
            skips["Contact.Employee_Number__c held by another contact (unique field; duplicate contact, Phase 2 merge)"].append(
                ("Contact", row["Id"], "%s wants %s; held by %s %s (%s)" % (row["Name"], num, id18(others[0]["Id"]), others[0]["Name"], others[0].get("Email"))))
            del row["Employee_Number__c_new"]; del row["Employee_Number__c_old"]; counts["Contact.Employee_Number__c"] -= 1; counts["Contact.Employee_Number__c skipped (held by duplicate)"] += 1

    # over-length guard (D3) - applies to Title on both objects
    for row in u_changes:
        if "Title_new" in row and len(row["Title_new"]) > 80:
            skips["Title over 80 (D3)"].append(("User", row["Id"], row["Title_new"])); del row["Title_new"]; del row["Title_old"]; counts["User.Title"] -= 1
    for row in c_changes:
        if "Title_new" in row and len(row["Title_new"]) > 128:
            skips["Title over 128 (D3)"].append(("Contact", row["Id"], row["Title_new"])); del row["Title_new"]; del row["Title_old"]; counts["Contact.Title"] -= 1
    u_changes = [r for r in u_changes if any(k.endswith("_new") for k in r)]
    c_changes = [r for r in c_changes if any(k.endswith("_new") for k in r)]

    # 5. filter-membership diff
    preds = load_predicates(meta_dir)
    movers = {"user_title": [], "manager": [], "contact_title": []}
    for row in u_changes:
        if "Title_new" not in row: continue
        for src, colname, op, val in preds["user_title"]:
            b, a2 = eval_pred(op, val, row["Title_old"]), eval_pred(op, val, row["Title_new"])
            if b is not None and b != a2: movers["user_title"].append((row["Id"], row["Name"], src, "%s %s '%s'" % (colname, op, val), "leaves" if b else "joins"))
    # manager graph after the batch, for Owner.Manager and Owner.Manager.Manager predicates
    new_mgr = {u: id18(r["ManagerId"]) for u, r in all_users.items()}
    for row in m_changes: new_mgr[row["Id"]] = row["ManagerId_new"]
    def mname(uid): return all_users[uid]["Name"] if uid in all_users else ""
    for row in m_changes:
        old1, new1 = mname(row["ManagerId_old"]), mname(row["ManagerId_new"])
        old2 = mname(id18(all_users[row["ManagerId_old"]]["ManagerId"])) if row["ManagerId_old"] in all_users else ""
        new2 = mname(new_mgr.get(row["ManagerId_new"], ""))
        for src, colname, op, val in preds["manager"]:
            second = "MANAGER.MANAGER" in colname.upper()
            b, a2 = eval_pred(op, val, old2 if second else old1), eval_pred(op, val, new2 if second else new1)
            if b is not None and b != a2: movers["manager"].append((row["Id"], row["Name"], src, "%s %s '%s'" % (colname, op, val), "leaves" if b else "joins"))
    seen = set()
    cpreds = [p for p in preds["contact_title"] if not (p[1:] in seen or seen.add(p[1:]))]   # de-duplicate identical predicates across reports
    for row in c_changes:
        if "Title_new" not in row: continue
        for src, colname, op, val in cpreds:
            b, a2 = eval_pred(op, val, row["Title_old"]), eval_pred(op, val, row["Title_new"])
            if b is not None and b != a2: movers["contact_title"].append((row["Id"], row["Name"], src, "%s %s '%s'" % (colname, op, val[:60]), "leaves" if b else "joins"))

    # 6. files
    def write_csv(path, rows, cols):
        with open(path, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=cols, lineterminator="\r\n", extrasaction="ignore"); w.writeheader()
            for r in rows: w.writerow({k: ("" if r.get(k) is None else r.get(k)) for k in cols})
    def cols_of(rows, fixed):
        c = list(fixed)
        for r in rows:
            for k in r:
                if k not in c: c.append(k)
        return c
    write_csv(os.path.join(out, "changes_user.csv"), u_changes, cols_of(u_changes, ["Id", "Name"]))
    write_csv(os.path.join(out, "changes_user_manager.csv"), m_changes, cols_of(m_changes, ["Id", "Name"]))
    write_csv(os.path.join(out, "changes_contact.csv"), c_changes, cols_of(c_changes, ["Id", "Name"]))

    def update_rows(rows, fields):
        outr = []
        for r in rows:
            d = {"Id": r["Id"]}
            for f in fields:
                if f + "_new" in r: d[f] = r[f + "_new"]
            outr.append(d)
        return outr
    def rollback_rows(rows, fields):
        outr = []
        for r in rows:
            d = {"Id": r["Id"]}
            for f in fields:
                if f + "_old" in r: d[f] = r[f + "_old"]
            outr.append(d)
        return outr
    def write_update(name, rows, fields):
        # Bulk API: every row must carry the same columns; blank cell = no change for sf data update bulk? NO - blank would clear. So split by column set.
        groups = collections.defaultdict(list)
        for r in rows:
            groups[tuple(k for k in fields if k in r)].append(r)
        n = 0
        combined = []
        for keyset, grp in groups.items():
            for i in range(0, len(grp), 200):
                n += 1
                write_csv(os.path.join(out, "parts", "%s_%03d.csv" % (name, n)), grp[i:i + 200], ["Id"] + list(keyset))
            combined += grp
        write_csv(os.path.join(out, name + ".csv"), combined, ["Id"] + fields)   # reference copy; parts/ are what gets loaded
        return n, len(groups)
    user_write = ["Title", "EmployeeNumber", "Employee_Code__c"] + wd_std + wd_present
    mgr_write = ["ManagerId"] + (["Workday_Last_Sync__c"] if "Workday_Last_Sync__c" in wd_present else [])
    nu, gu = write_update("update_user", update_rows(u_changes, user_write), user_write)
    nm, gm = write_update("update_user_manager", update_rows(m_changes, mgr_write), mgr_write)
    nc, gc = write_update("update_contact", update_rows(c_changes, CONTACT_FIELDS), CONTACT_FIELDS)
    write_update("rollback_user", rollback_rows(u_changes, user_write), user_write)
    write_update("rollback_user_manager", rollback_rows(m_changes, mgr_write), mgr_write)
    write_update("rollback_contact", rollback_rows(c_changes, CONTACT_FIELDS), CONTACT_FIELDS)

    ub = [{"Id": u} | {k: ("true" if v is True else "false" if v is False else v) for k, v in r.items() if k != "Id"} for u, r in users.items()]
    cb = [{"Id": c} | {k: ("true" if v is True else "false" if v is False else v) for k, v in r.items() if k != "Id"} for c, r in contacts.items()]
    write_csv(os.path.join(out, "backup_%s_%s_User.csv" % (org["orgId"], ts)), ub, ["Id"] + user_fields + USER_BASELINE)
    write_csv(os.path.join(out, "backup_%s_%s_Contact.csv" % (org["orgId"], ts)), cb, ["Id"] + CONTACT_FIELDS + CONTACT_BASELINE)

    # 7. report
    L = []
    L.append("# Dry run report: %s (Step 1, no DML)\n" % alias)
    L.append("Generated %s. Org %s (%s), user %s. HR extract: %s. Mapping: %s.\n" % (ts, org["orgId"], org["instance"], org["username"], os.path.basename(a.hr), os.path.basename(a.mapping)))
    L.append("Sandbox mode: %s (missing/inactive Ids are logged and skipped; production aborts).\n" % is_sandbox)
    L.append("## Counts\n")
    L.append("| Object | Records in scope | Found | Skipped (missing) | Skipped (inactive) | Rows with a change |\n|---|---|---|---|---|---|")
    L.append("| User (title/number/code batch) | %d | %d | %d | %d | %d |" % (len(in_users), len(users), len(missing_u), len(inactive_u), len(u_changes)))
    L.append("| User (manager batch, D2) | %d | %d | %d | %d | %d |" % (len(in_users), len(users), len(missing_u), len(inactive_u), len(m_changes)))
    L.append("| Contact | %d | %d | %d | | %d |\n" % (len(in_contacts), len(contacts), len(missing_c), len(c_changes)))
    L.append("| Field | Would change | Already equal | Blank in HR (skipped, not cleared) | Brief expected |\n|---|---|---|---|---|")
    exp = {"User.Title": "about 194", "User.EmployeeNumber": "about 309", "User.Employee_Code__c": "about 224", "User.ManagerId": "about 92",
           "Contact.Employee_Number__c": "about 559", "Contact.Title": "about 596", "Contact.Not_at_Company_Checkbox__c": "about 9 across the three flags",
           "Contact.No_Longer_w_Company__c": "", "Contact.ADvendio__LeftCompany__c": ""}
    for f in exp:
        L.append("| %s | %d | %d | %d | %s |" % (f, counts[f], counts[f + " equal"], counts[f + " blank in HR (skipped)"], exp[f]))
    L.append("\n### Workday extension fields (team brief, 8 Sep 2026)\n")
    L.append("Custom fields present in %s: %s. Missing (not written until the metadata is deployed here): %s.\n" % (alias, wd_present or "none", wd_missing or "none"))
    L.append("| Field | Would change | Already equal | Blank in HR | Skipped (value / picklist / unresolved) |\n|---|---|---|---|---|")
    for f in WORKDAY_STD_FIELDS + WORKDAY_CUSTOM_FIELDS:
        if f == "Workday_Last_Sync__c":
            L.append("| User.%s | stamped on every changed row (%d user + %d manager) | | | |" % (f, sum(1 for r in u_changes if "Workday_Last_Sync__c_new" in r), sum(1 for r in m_changes if "Workday_Last_Sync__c_new" in r))); continue
        sk = counts["User.%s skipped (value)" % f] + counts["User.%s skipped (picklist)" % f] + counts["User.%s skipped (unresolved)" % f]
        L.append("| User.%s | %d | %d | %d | %d%s |" % (f, counts["User." + f], counts["User.%s equal" % f], counts["User.%s blank in HR (skipped)" % f], sk, "" if f in present else " (not in org)"))
    L.append("\nD6 hold (Kam, 8 Sep 2026, answer 3): User fields held = %s. Rows that would change but are held: EmployeeNumber %d, Employee_Code__c %d. Release with --hold-fields '' once Finance has remapped the SUN extract.\n" % (
        sorted(hold) or "none", counts["User.EmployeeNumber held (D6)"], counts["User.Employee_Code__c held (D6)"]))
    L.append("\nManagerId skipped: unresolved %d, manager Id missing in org %d, manager inactive in org %d. Manager names matched after stripping '(On Leave)': %d.\n" % (
        counts["User.ManagerId skipped (unresolved)"], counts["User.ManagerId skipped (manager Id missing in org)"], counts["User.ManagerId skipped (manager inactive in org)"], stripped))
    L.append("Employee IDs with a leading zero: %d in the workbook, %d in the change set (read as text: %d non-text cells).\n" % (
        lead_zero, sum(1 for r in u_changes + c_changes for k in ("EmployeeNumber_new", "Employee_Number__c_new") if r.get(k, "x").startswith("0")), non_str))
    L.append("Name check: %d users and %d contacts pass; %d failed and were skipped (sandbox exception); %d excused via name_check_exceptions.csv. Failures are listed under Skipped rows and in name_check_candidates.csv for Gate 1.\n" % (len(users), len(contacts), len(bad), len(excused)))
    L.append("Update files: user %d part(s) in %d column-set(s), manager %d/%d, contact %d/%d (parts/ are loaded one after another; each part carries only the columns it changes so a blank never clears a value).\n" % (nu, gu, nm, gm, nc, gc))
    L.append("## Skipped rows\n")
    for reason, items in skips.items():
        L.append("### %s (%d)\n" % (reason, len(items)))
        for it in items[:60]: L.append("- %s %s %s" % it)
        if len(items) > 60: L.append("- ... %d more (see run log)" % (len(items) - 60))
        L.append("")
    L.append("### ManagerId unresolved (%d)\n" % len(mgr_skips))
    for it in mgr_skips[:80]: L.append("- %s %s: %s" % it)
    if len(mgr_skips) > 80: L.append("- ... %d more" % (len(mgr_skips) - 80))
    L.append("\n## Flagged contacts (D4, D5)\n")
    L.append("| Id | Name | Account | Flags now | DoNotCall | Email opt-out | No_Postal | LID |\n|---|---|---|---|---|---|---|---|")
    for c, r in contacts.items():
        if r["Not_at_Company_Checkbox__c"] or r["No_Longer_w_Company__c"] or r["ADvendio__LeftCompany__c"]:
            L.append("| %s | %s | %s | NAC=%d NLW=%d ADV=%d | %d | %d | %d | %s |" % (c, r["Name"], r["Account.Name"], bool(r["Not_at_Company_Checkbox__c"]), bool(r["No_Longer_w_Company__c"]), bool(r["ADvendio__LeftCompany__c"]), bool(r["DoNotCall"]), bool(r["HasOptedOutOfEmail"]), bool(r["No_Postal__c"]), r["LID__No_longer_at_Company__c"]))
    L.append("\n## Filter-membership diff (report and list-view predicates from %s)\n" % ("preflight metadata" if any(preds.values()) else "NONE - metadata dir not found"))
    L.append("Predicates loaded: user title %d, manager %d, contact title %d (%d distinct).\n" % (len(preds["user_title"]), len(preds["manager"]), len(preds["contact_title"]), len(cpreds)))
    for k, label in (("user_title", "User Title predicates"), ("manager", "Manager-name predicates"), ("contact_title", "Contact Title persona predicates")):
        mv = movers[k]
        L.append("### %s: %d membership changes across %d records\n" % (label, len(mv), len({m[0] for m in mv})))
        for m in mv[:60]: L.append("- %s %s %s %s: %s" % (m[0], m[1], m[4], m[3], m[2]))
        if len(mv) > 60: L.append("- ... %d more" % (len(mv) - 60))
        L.append("")
    L.append("## Samples (first 20 per object)\n")
    for name, rows in (("changes_user.csv", u_changes), ("changes_user_manager.csv", m_changes), ("changes_contact.csv", c_changes)):
        L.append("### %s\n" % name)
        if not rows: L.append("(no rows)\n"); continue
        cols = cols_of(rows, ["Id", "Name"])
        L.append("| " + " | ".join(cols) + " |"); L.append("|" + "---|" * len(cols))
        for r in rows[:20]: L.append("| " + " | ".join(str(r.get(k, "")).replace("|", "/") for k in cols) + " |")
        L.append("")
    L.append("## Decisions restated (defaults unless Kam changes them at Gate 1)\n")
    L.append("- D1: Employee_Code__c on User mirrors EmployeeNumber (same HR value).")
    L.append("- D2: manager changes are a separate batch (changes_user_manager.csv). sbaa cleared in preflight; visible in case escalation and %d manager-name report predicates. Apply to production only on Kam's acceptance." % len(preds["manager"]))
    L.append("- D3: over-length titles are skipped, never truncated (this run: %d)." % (len(skips["Title over 80 (D3)"]) + len(skips["Title over 128 (D3)"])))
    L.append("- D4: the forced opt-outs on flagged contacts are left as they are.")
    L.append("- D5: LID__No_longer_at_Company__c is not touched; the active copy flow fires only on a LID change.")
    L.append("- D6: EmployeeNumber (and the D1 mirror) go to production only after Finance confirms the SUN extract does not key on it.")
    L.append("- Blank in HR means skip, never clear. Manager_Email__c is a formula and is not written.")
    open(os.path.join(out, "dry_run_report.md"), "w", encoding="utf-8", newline="\n").write("\n".join(L))
    open(os.path.join(out, "run_%s.log" % ts), "w", encoding="utf-8").write("\n".join(log) + "\n\nskips=" + json.dumps({k: v for k, v in skips.items()}, indent=1) + "\n\nmanager_skips=" + json.dumps(mgr_skips, indent=1))
    # machine-readable skip list for verify: "<Id>|<field or *>" -> reason
    skipped_ids = {}
    for reason, items in skips.items():
        if "excused" in reason: continue   # excused rows were written; verify must check them
        for it in items:
            m = re.match(r"User\.(\w+) ", reason)
            fld = m.group(1) if m else "Employee_Number__c" if "Employee_Number__c held" in reason else "Title" if "Title over" in reason else "*"
            skipped_ids["%s|%s" % (it[1], fld)] = reason
    for u, n, why in mgr_skips: skipped_ids["%s|ManagerId" % u] = why
    json.dump(skipped_ids, open(os.path.join(out, "skipped_ids.json"), "w", encoding="utf-8"), indent=1)
    with open(os.path.join(out, "name_check_candidates.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, lineterminator="\r\n"); w.writerow(["Object", "Id", "Org Name", "HR Worker", "Decision (write / exclude)"])
        for b in bad: w.writerow([b[0], b[1], b[2], b[3], ""])
    say("Wrote", out)

if __name__ == "__main__":
    main()
