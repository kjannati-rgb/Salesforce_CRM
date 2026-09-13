"""Step 2 / Step 3 apply: load the update parts with Bulk API 2.0 (sf data update bulk), one file at a time.

Usage: python apply.py --org FULLUAT [--batches user,contact,manager] [--dry]
Stops immediately when a part's failures exceed 1 percent or any failure is a validation-rule or flow error.
Writes out_<org>/jobs/<jobId>-{success,failed}-records.csv and out_<org>/runs/<timestamp>.md.
"""
import argparse, csv, datetime, glob, json, os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
PROD_ORG_ID = "00D6g0000081IOg"
SANDBOX_ALIASES = {"FULLUAT", "KJDEV"}
for v in ("HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy"):
    os.environ.pop(v, None)

def sf_json(args, cwd=None):
    o = subprocess.run(["sf"] + args + ["--json"], capture_output=True, text=True, shell=True, encoding="utf-8", cwd=cwd)
    txt = o.stdout
    i = txt.find("{")
    if i < 0:
        raise RuntimeError("sf returned no JSON: " + (o.stderr or txt)[:800])
    return json.loads(txt[i:])

def query(alias, soql):
    j = sf_json(["data", "query", "--target-org", alias, "--query", soql])
    if j.get("status") != 0:
        raise RuntimeError(json.dumps(j)[:800])
    return j["result"]["records"]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--org", required=True)
    ap.add_argument("--batches", default="user,contact,manager")
    ap.add_argument("--dry", action="store_true", help="print the commands, load nothing")
    ap.add_argument("--parts-dir", default=None, help="folder holding parts/ to load (default out_<org>); jobs/ and runs/ always go to out_<org>")
    a = ap.parse_args()
    alias = a.org
    is_sandbox = alias.upper() in SANDBOX_ALIASES
    out = os.path.join(HERE, "out_%s" % alias)
    parts_root = a.parts_dir or out
    jobs_dir = os.path.join(out, "jobs"); os.makedirs(jobs_dir, exist_ok=True)
    runs_dir = os.path.join(out, "runs"); os.makedirs(runs_dir, exist_ok=True)
    ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d_%H%M%S")
    L = []
    def say(*x):
        s = " ".join(str(i) for i in x); print(s, flush=True); L.append(s)

    org = sf_json(["org", "display", "--target-org", alias])["result"]
    say("# Apply run %s on %s" % (ts, alias))
    say("Org Id %s, user %s, instance %s" % (org["id"], org["username"], org.get("instanceUrl")))
    if is_sandbox and org["id"].startswith(PROD_ORG_ID): sys.exit("ABORT: sandbox alias resolved to production")
    if not is_sandbox and not org["id"].startswith(PROD_ORG_ID): sys.exit("ABORT: production alias does not resolve to %s" % PROD_ORG_ID)
    if not is_sandbox and os.environ.get("GO_PROD") != "GO PROD": sys.exit("ABORT: production apply requires env GO_PROD='GO PROD' set by Kam's literal reply")

    start_utc = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    try:
        pre = query(alias, "SELECT COUNT() FROM Flow_Log__c")
        flow_log_pre = sf_json(["data", "query", "--target-org", alias, "--query", "SELECT COUNT() FROM Flow_Log__c"])["result"]["totalSize"]
    except Exception as e:
        flow_log_pre = "n/a (%s)" % str(e)[:100]
    say("Run start (UTC): %s | Flow_Log__c count before: %s" % (start_utc, flow_log_pre))
    json.dump({"start_utc": start_utc, "flow_log_pre": flow_log_pre, "org": org["id"]}, open(os.path.join(out, "run_start_%s.json" % ts), "w"))

    order = []
    names = {"user": ("User", "update_user_0"), "contact": ("Contact", "update_contact_0"), "manager": ("User", "update_user_manager_0")}
    for b in a.batches.split(","):
        sobj, prefix = names[b.strip()]
        for f in sorted(glob.glob(os.path.join(parts_root, "parts", prefix + "*.csv"))):
            order.append((b.strip(), sobj, f))
    say("Parts to load, in order: %d" % len(order))
    totals = {"processed": 0, "failed": 0}
    retry_rows = []   # (sobject, header, row) for UNABLE_TO_LOCK_ROW retries
    stop = None
    for batch, sobj, f in order:
        n = sum(1 for _ in open(f, encoding="utf-8")) - 1
        cmd = ["data", "update", "bulk", "--sobject", sobj, "--file", f, "--wait", "10", "--line-ending", "CRLF", "--target-org", alias]
        say("\n## %s  (%s, %d rows)" % (os.path.basename(f), sobj, n))
        say("`sf " + " ".join(cmd) + "`")
        if a.dry:
            continue
        t0 = time.time()
        j = sf_json(cmd)
        r = j.get("result") or {}
        job = r.get("jobInfo", r)
        job_id = job.get("id") or r.get("jobId") or (j.get("data") or {}).get("jobId")   # FailedRecordDetailsError carries the id in data.jobId
        processed = job.get("numberRecordsProcessed"); failed = job.get("numberRecordsFailed"); state = job.get("state")
        say("job %s state %s processed %s failed %s in %.0fs (cli status %s)" % (job_id, state, processed, failed, time.time() - t0, j.get("status")))
        if j.get("status") != 0 and not job_id:
            say("CLI error: " + json.dumps(j)[:1500]); stop = "CLI error on %s" % os.path.basename(f); break
        # results files
        res = sf_json(["data", "bulk", "results", "--job-id", job_id, "--target-org", alias], cwd=jobs_dir)
        say("results: " + json.dumps(res.get("result"))[:400])
        failed_file = os.path.join(jobs_dir, "%s-failed-records.csv" % job_id)
        fails = []
        if os.path.exists(failed_file):
            with open(failed_file, encoding="utf-8") as fh:
                fails = list(csv.DictReader(fh))
        totals["processed"] += int(processed or 0); totals["failed"] += len(fails)
        if fails:
            say("failures (%d):" % len(fails))
            errs = {}
            for row in fails:
                msg = row.get("sf__Error", "")
                errs.setdefault(msg[:160], 0); errs[msg[:160]] += 1
            for m, c in errs.items(): say("  %dx %s" % (c, m))
            lock = [row for row in fails if "UNABLE_TO_LOCK_ROW" in row.get("sf__Error", "")]
            hard = [row for row in fails if any(k in row.get("sf__Error", "") for k in ("FIELD_CUSTOM_VALIDATION_EXCEPTION", "FLOW", "Flow", "flow"))]
            if hard:
                stop = "validation-rule or flow error in %s" % os.path.basename(f)
                for row in hard[:10]: say("  VERBATIM: " + row.get("sf__Error", ""))
                break
            if len(fails) - len(lock) > 0.01 * n:
                stop = "failures exceed 1 percent in %s" % os.path.basename(f); break
            hdr = [h for h in fails[0].keys() if not h.startswith("sf__")]
            for row in lock: retry_rows.append((sobj, hdr, {h: row[h] for h in hdr}))
    if retry_rows and not stop and not a.dry:
        say("\n## Retrying %d UNABLE_TO_LOCK_ROW rows once" % len(retry_rows))
        by = {}
        for sobj, hdr, row in retry_rows: by.setdefault((sobj, tuple(hdr)), []).append(row)
        for (sobj, hdr), rows in by.items():
            rf = os.path.join(out, "parts", "retry_%s_%s.csv" % (sobj, ts))
            with open(rf, "w", newline="", encoding="utf-8") as fh:
                w = csv.DictWriter(fh, fieldnames=list(hdr), lineterminator="\r\n"); w.writeheader(); w.writerows(rows)
            j = sf_json(["data", "update", "bulk", "--sobject", sobj, "--file", rf, "--wait", "10", "--line-ending", "CRLF", "--target-org", alias])
            job = (j.get("result") or {}).get("jobInfo", j.get("result") or {})
            say("retry job %s processed %s failed %s" % (job.get("id"), job.get("numberRecordsProcessed"), job.get("numberRecordsFailed")))
            sf_json(["data", "bulk", "results", "--job-id", job.get("id"), "--target-org", alias], cwd=jobs_dir)
    say("\n## Totals: processed %d, failed %d. %s" % (totals["processed"], totals["failed"], ("STOPPED: " + stop) if stop else "completed"))
    open(os.path.join(runs_dir, "%s.md" % ts), "w", encoding="utf-8").write("\n".join(L) + "\n")
    if stop: sys.exit(2)

if __name__ == "__main__":
    main()
