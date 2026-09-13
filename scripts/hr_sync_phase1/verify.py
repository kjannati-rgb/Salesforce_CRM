"""Step 2.4 / 3.4 verify: re-query every in-scope Id, diff against the intended values with the Step 1.6 comparison rules,
check the baseline fields for side effects, count Flow_Log__c entries since the run start, and re-run the build for the
idempotency count. Writes out_<org>/verify_<label>.md.

Usage: python verify.py --org FULLUAT --label sandbox [--second-read]
--second-read: only re-check the three flags on the flagged contacts (run a few minutes after the first verify).
"""
import argparse, csv, datetime, glob, json, os, subprocess, sys, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_changes import same_title, same_exact, id18, fetch_by_ids, query, org_display, USER_FIELDS, USER_BASELINE, CONTACT_FIELDS, CONTACT_BASELINE, HERE

def read_csv(p):
    with open(p, encoding="utf-8") as f:
        return list(csv.DictReader(f))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--org", required=True); ap.add_argument("--label", default=None); ap.add_argument("--second-read", action="store_true")
    ap.add_argument("--users-only", action="store_true", help="pass through to the idempotency rebuild (KJDEV smoke tests)")
    ap.add_argument("--intent-dir", default=None, help="continuation folder whose changes_*.csv and backups are the intent to verify (default out_<org>)")
    ap.add_argument("--no-workday", action="store_true", help="pass through to the idempotency rebuild (Phase 1 scope)")
    ap.add_argument("--skip-batches", default="", help="comma list of batches not yet loaded (e.g. manager): their rows are reported as pending, not mismatches")
    a = ap.parse_args()
    alias = a.org; label = a.label or ("sandbox" if alias != "PROD" else "prod")
    out = os.path.join(HERE, "out_%s" % alias)
    intent = a.intent_dir or out
    org = org_display(alias)
    L = ["# Verify: %s (%s)\n" % (alias, label), "Generated %s UTC. Org %s, user %s.\n" % (datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S"), org["orgId"], org["username"])]
    say = lambda s: (print(s, flush=True), L.append(s))

    starts = sorted(glob.glob(os.path.join(out, "run_start_*.json")))
    # window: earliest run start for the main folder, latest for a continuation (its own load is the newest)
    start = json.load(open(starts[-1] if a.intent_dir else starts[0])) if starts else {}
    changes = {"User": read_csv(os.path.join(intent, "changes_user.csv")), "Manager": read_csv(os.path.join(intent, "changes_user_manager.csv")), "Contact": read_csv(os.path.join(intent, "changes_contact.csv"))}
    ubk = sorted(glob.glob(os.path.join(intent, "backup_*_User.csv")))[-1]; cbk = sorted(glob.glob(os.path.join(intent, "backup_*_Contact.csv")))[-1]
    backup = {"User": {r["Id"]: r for r in read_csv(ubk)}, "Contact": {r["Id"]: r for r in read_csv(cbk)}}
    say("Baseline: %s (%d users), %s (%d contacts). Run start: %s, Flow_Log__c before: %s\n" % (os.path.basename(ubk), len(backup["User"]), os.path.basename(cbk), len(backup["Contact"]), start.get("start_utc"), start.get("flow_log_pre")))

    # fetch every field the change set intends to write (the Workday extension adds fields per org), plus the baseline
    intended_fields = {k[:-4] for rows in changes.values() for r in rows for k in r if k.endswith("_new")} - {"Manager", "ELT_Lead_name"}
    user_fetch = list(dict.fromkeys(USER_FIELDS + sorted(f for f in intended_fields if f not in CONTACT_FIELDS) + USER_BASELINE))
    users_now = fetch_by_ids(alias, "User", backup["User"].keys(), user_fetch)
    contacts_now = fetch_by_ids(alias, "Contact", backup["Contact"].keys(), CONTACT_FIELDS + CONTACT_BASELINE)

    if a.second_read:
        say("## Second read of the three flags\n")
        bad = 0
        for r in changes["Contact"]:
            if r.get("Not_at_Company_Checkbox__c_new") or r.get("No_Longer_w_Company__c_new") or r.get("ADvendio__LeftCompany__c_new"):
                c = contacts_now.get(r["Id"], {})
                flags = (c.get("Not_at_Company_Checkbox__c"), c.get("No_Longer_w_Company__c"), c.get("ADvendio__LeftCompany__c"))
                ok = not any(flags); bad += 0 if ok else 1
                say("- %s %s: NAC=%s NLW=%s ADV=%s LID=%s -> %s" % (r["Id"], r["Name"], *[int(bool(x)) for x in flags], c.get("LID__No_longer_at_Company__c"), "still clear" if ok else "RE-SET"))
        say("\nSecond read: %d re-set" % bad)
        open(os.path.join(out, "verify_%s_second_read.md" % label), "w", encoding="utf-8").write("\n".join(L)); return

    # 1. intended values
    say("## Intended values\n")
    tot = collections.Counter()
    mism = []
    skipped = {}
    for sp in [os.path.join(out, "skipped_ids.json")] + sorted(glob.glob(os.path.join(out, "continue*", "skipped_ids.json"))):
        if os.path.exists(sp): skipped.update(json.load(open(sp, encoding="utf-8")))
    skipped_hits = []
    def check(obj, rows, now, cmp):
        for r in rows:
            cur = now.get(r["Id"])
            if cur is None: tot[obj + " missing now"] += 1; mism.append((obj, r["Id"], r.get("Name"), "record not found")); continue
            for k in r:
                if not k.endswith("_new"): continue
                f = k[:-4]; want = r[k]
                if want == "" or f in ("Manager", "Manager_Email__c_expected", "ELT_Lead_name"): continue   # empty cell = field not changed on this row; name columns are informational
                if f == "Workday_Last_Sync__c":
                    ok = bool(cur.get(f)) and str(cur.get(f)) >= want[:19]   # stamped at or after the build time
                    tot[obj + " fields checked"] += 1; tot[obj + (" match" if ok else " MISMATCH")] += 1
                    if not ok: mism.append((obj, r["Id"], r.get("Name"), "Workday_Last_Sync__c not stamped (have %r)" % cur.get(f)))
                    continue
                if f == "Hire_Date__c":
                    ok = (str(cur.get(f) or "")[:10] == want); tot[obj + " fields checked"] += 1; tot[obj + (" match" if ok else " MISMATCH")] += 1
                    if not ok: mism.append((obj, r["Id"], r.get("Name"), "Hire_Date__c: have %r want %r" % (cur.get(f), want)))
                    continue
                if ("%s|%s" % (r["Id"], f)) in skipped or ("%s|*" % r["Id"]) in skipped:
                    tot[obj + " skipped (logged)"] += 1; skipped_hits.append((obj, r["Id"], r.get("Name"), f, skipped.get("%s|%s" % (r["Id"], f)) or skipped.get("%s|*" % r["Id"]))); continue
                have = cur.get(f)
                if f in ("Not_at_Company_Checkbox__c", "No_Longer_w_Company__c", "ADvendio__LeftCompany__c"):
                    ok = (str(bool(have)).lower() == want.lower())
                else:
                    ok = cmp.get(f, same_exact)(have, want)
                tot[obj + " fields checked"] += 1
                if ok: tot[obj + " match"] += 1
                else: tot[obj + " MISMATCH"] += 1; mism.append((obj, r["Id"], r.get("Name"), "%s: have %r want %r" % (f, have, want)))
    pending = {b.strip() for b in a.skip_batches.split(",") if b.strip()}
    check("User", changes["User"], users_now, {"Title": same_title, "Department": same_title, "CompanyName": same_title, "Division": same_title, "ELT_Lead__c": lambda h, w: id18(h) == w})
    if "manager" in pending: say("- Manager batch: %d rows PENDING (not loaded yet; not checked)" % len(changes["Manager"]))
    else: check("Manager", changes["Manager"], users_now, {"ManagerId": lambda h, w: id18(h) == w})
    check("Contact", changes["Contact"], contacts_now, {"Title": same_title})
    for k in sorted(tot): say("- %s: %d" % (k, tot[k]))
    if skipped_hits:
        say("\nIntended but skipped with a logged reason (counted as pass):"); [say("- %s %s %s %s: %s" % h) for h in skipped_hits[:60]]
    if mism:
        say("\nMismatches:"); [say("- %s %s %s: %s" % m) for m in mism[:100]]
    # Manager_Email__c derived check
    me_bad = [(r["Id"], r["Name"], users_now[r["Id"]].get("Manager_Email__c"), users_now[r["Id"]].get("Manager.Email")) for r in changes["Manager"] if r["Id"] in users_now and (users_now[r["Id"]].get("Manager_Email__c") or "") != (users_now[r["Id"]].get("Manager.Email") or "")]
    say("\nManager_Email__c (formula) equals Manager.Email on %d of %d manager-batch users%s" % (len(changes["Manager"]) - len(me_bad), len(changes["Manager"]), "" if not me_bad else "; exceptions: " + str(me_bad[:5])))

    # 2. side effects: baseline fields that moved, and records touched that we did not update
    say("\n## Side effects\n")
    touched = {r["Id"] for rows in changes.values() for r in rows}
    side = collections.Counter(); side_rows = []
    def tostr(v): return "true" if v is True else "false" if v is False else ("" if v is None else str(v))
    for obj, bk, now, watch in (("User", backup["User"], users_now, ["Email", "IsActive", "Name"]), ("Contact", backup["Contact"], contacts_now, ["Email", "AccountId", "LID__No_longer_at_Company__c", "DoNotCall", "HasOptedOutOfEmail", "No_Postal__c", "ReportsToId", "Name"])):
        for rid, old in bk.items():
            cur = now.get(rid)
            if cur is None: continue
            for f in watch:
                if tostr(cur.get(f)) != old.get(f, ""):
                    side[obj + "." + f] += 1; side_rows.append((obj, rid, old.get("Name"), f, old.get(f, ""), tostr(cur.get(f))))
            if tostr(cur.get("SystemModstamp")) != old.get("SystemModstamp", "") and rid not in touched:
                side[obj + " modified by something else (not in our update set)"] += 1; side_rows.append((obj, rid, old.get("Name"), "SystemModstamp", old.get("SystemModstamp"), tostr(cur.get("SystemModstamp"))))
    if not side: say("No baseline field moved and no untouched record was modified.")
    for k, v in side.items(): say("- %s: %d" % (k, v))
    for s in side_rows[:60]: say("  - %s %s %s %s: %r -> %r" % s)
    by_other = collections.Counter()
    for obj, now in (("User", users_now), ("Contact", contacts_now)):
        for rid, cur in now.items():
            if rid in touched and cur.get("LastModifiedById") and id18(cur["LastModifiedById"]) != id18(org.get("userId", "")):
                by_other[obj] += 1
    say("\nLastModifiedById check skipped where org user id unknown; touched records: users %d, contacts %d." % (sum(1 for r in changes["User"] + changes["Manager"]), len(changes["Contact"])))

    # 3. Flow_Log__c since start
    say("\n## Flow_Log__c since run start\n")
    if start.get("start_utc"):
        try:
            o = subprocess.run(["sf", "data", "query", "--target-org", alias, "--query", "SELECT COUNT() FROM Flow_Log__c WHERE CreatedDate >= %s" % start["start_utc"], "--json"], capture_output=True, text=True, shell=True, encoding="utf-8").stdout
            cnt = json.loads(o[o.find("{"):])["result"]["totalSize"]
            say("Entries created since %s: %d (count before run: %s)" % (start["start_utc"], cnt, start.get("flow_log_pre")))
            if cnt:
                recs = query(alias, "SELECT Id, Name, CreatedDate FROM Flow_Log__c WHERE CreatedDate >= %s ORDER BY CreatedDate LIMIT 20" % start["start_utc"])
                for r in recs: say("- %s %s %s" % (r["Id"], r.get("Name"), r.get("CreatedDate")))
        except Exception as e:
            say("Flow_Log__c query failed: %s" % str(e)[:300])
    else:
        say("No run_start file found; cannot window Flow_Log__c.")

    # 4. idempotency: rebuild and count
    say("\n## Idempotency\n")
    o = subprocess.run([sys.executable, os.path.join(HERE, "build_changes.py"), "--org", alias, "--out", os.path.join(out, "idempotency_check")] + (["--users-only"] if a.users_only else []) + (["--no-workday"] if a.no_workday else []), capture_output=True, text=True, shell=True, encoding="utf-8", env=dict(os.environ, PYTHONIOENCODING="utf-8"))
    ic = os.path.join(out, "idempotency_check")
    counts = {n: max(0, sum(1 for _ in open(os.path.join(ic, n), encoding="utf-8")) - 1) for n in ("changes_user.csv", "changes_user_manager.csv", "changes_contact.csv") if os.path.exists(os.path.join(ic, n))}
    say("Second build against the updated org: %s (must be zero for every batch that was applied)" % counts)
    if o.returncode != 0: say("build exit %d: %s" % (o.returncode, (o.stdout + o.stderr)[-800:]))

    # 5. flags first read
    say("\n## Flags after the run (first read)\n")
    for r in changes["Contact"]:
        if r.get("Not_at_Company_Checkbox__c_new") or r.get("No_Longer_w_Company__c_new") or r.get("ADvendio__LeftCompany__c_new"):
            c = contacts_now.get(r["Id"], {})
            say("- %s %s: NAC=%d NLW=%d ADV=%d DNC=%d EOO=%d NoPost=%d LID=%s" % (r["Id"], r["Name"], bool(c.get("Not_at_Company_Checkbox__c")), bool(c.get("No_Longer_w_Company__c")), bool(c.get("ADvendio__LeftCompany__c")), bool(c.get("DoNotCall")), bool(c.get("HasOptedOutOfEmail")), bool(c.get("No_Postal__c")), c.get("LID__No_longer_at_Company__c")))
    if alias != "PROD":
        say("\nSandbox caveat: Full UAT user emails carry the .invalid suffix from the refresh, so Manager_Email__c values here are not the production values. This run proves the mechanics of the manager batch, not its data.")
    open(os.path.join(out, "verify_%s.md" % label), "w", encoding="utf-8", newline="\n").write("\n".join(L))
    print("wrote", os.path.join(out, "verify_%s.md" % label))

if __name__ == "__main__":
    main()
