#!/usr/bin/env python3
"""
G300 Firm Account Dedup Sweep
==============================

Identifies candidate duplicate Account records (RecordType = Firm) for the
302 accounts flagged G300_Account__c = true, using four independent signals:

  Pass 2 - Website exact match
  Pass 3 - Normalized full-name prefix match (suffix-stripped: LLP/LLC/PC/etc.)
  Pass 4 - Cross-reference on other unique identifiers (LEI, BvD ID, ALM
           Account ID, LinkedIn Company ID, Trade Register Number)
  Pass 5 - Structural / completeness gaps on the G300 records themselves
           (zero offices, blank website, blank segmentation)

This is a READ-ONLY identification pass. It does NOT merge or write anything.
Output is two CSVs for manual review before any merge is executed - per the
CE-master lesson from 24 Sep, merge direction must be confirmed by a human,
not inferred by this script.

Usage:
    python3 g300_dedup_sweep.py --target-org <alias-or-username>

Requires:
    Salesforce CLI (`sf`) installed and authenticated to the target org.
    This script shells out to `sf data query --json`.

Outputs (written to ./output/):
    g300_duplicate_candidates.csv   - candidate duplicate pairs + signal(s)
    g300_completeness_gaps.csv      - G300 records themselves missing key data
    g300_sweep_summary.txt          - run summary / counts
"""

import argparse
import csv
import json
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

FIRM_RECORD_TYPE_ID = "0126g000000OhUSAA0"

# Fields used for the cross-identifier check (Pass 4). Add/remove as your
# org's data quality on these fields changes over time.
IDENTIFIER_FIELDS = [
    "LEI_Legal_Entity_Identifier__c",
    "BvD_ID_Number__c",
    "Orbis_ID__c",
    "ALM_Account_ID__c",
    "SF_ALM_ID__c",
    "LID__LinkedIn_Company_Id__c",
    "Trade_Register_Number__c",
]

BASE_FIELDS = [
    "Id", "Name", "Website", "No_of_Offices__c", "Model_Segmentation__c",
    "CreatedDate",
] + IDENTIFIER_FIELDS

SUFFIX_RE = re.compile(
    r'\s*[,]?\s*(L\.?L\.?P\.?|L\.?L\.?C\.?|P\.?L\.?L\.?C\.?|P\.?L\.?C\.?|'
    r'P\.?C\.?|P\.?A\.?|L\.?P\.?|LPC|N\.?V\.?|S\.?L\.?P\.?|GmbH.*|'
    r'Professional Corporation|Verein)\s*\.?\s*$',
    re.IGNORECASE,
)


def strip_suffix(name: str) -> str:
    """Iteratively strip trailing legal-entity suffixes to get a comparable core name."""
    prev, n = None, name.strip()
    while prev != n:
        prev = n
        n = SUFFIX_RE.sub('', n).strip().rstrip(',').strip()
    return n


def sf_query(query: str, target_org: str) -> list:
    """Run a SOQL query via the Salesforce CLI and return the record list."""
    cmd = ["sf", "data", "query", "--query", query, "--json"]
    if target_org:
        cmd += ["--target-org", target_org]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"[ERROR] Query failed:\n{query}\n{result.stderr}", file=sys.stderr)
        return []
    payload = json.loads(result.stdout)
    return payload.get("result", {}).get("records", [])


def esc(s: str) -> str:
    return s.replace("\\", "\\\\").replace("'", "\\'")


def chunk(lst, size):
    for i in range(0, len(lst), size):
        yield lst[i:i + size]


def fetch_g300_firms(target_org: str) -> list:
    fields = ", ".join(BASE_FIELDS)
    query = (
        f"SELECT {fields} FROM Account "
        f"WHERE RecordTypeId = '{FIRM_RECORD_TYPE_ID}' "
        f"AND G300_Account__c = true ORDER BY Name"
    )
    return sf_query(query, target_org)


def pass2_website_match(g300_firms: list, target_org: str) -> list:
    """Find non-G300 Firm accounts sharing a G300 firm's exact Website."""
    candidates = []
    websites = sorted({f["Website"] for f in g300_firms if f.get("Website")})
    by_website = defaultdict(list)
    for f in g300_firms:
        if f.get("Website"):
            by_website[f["Website"]].append(f)

    for batch in chunk(websites, 60):
        in_list = ",".join(f"'{esc(w)}'" for w in batch)
        query = (
            f"SELECT Id, Name, Website FROM Account "
            f"WHERE RecordTypeId = '{FIRM_RECORD_TYPE_ID}' "
            f"AND G300_Account__c = false AND Website IN ({in_list})"
        )
        for rec in sf_query(query, target_org):
            for g300 in by_website.get(rec["Website"], []):
                candidates.append({
                    "signal": "website_exact_match",
                    "g300_id": g300["Id"], "g300_name": g300["Name"],
                    "candidate_id": rec["Id"], "candidate_name": rec["Name"],
                    "candidate_website": rec.get("Website") or "",
                })
    return candidates


def pass3_normalized_name_match(g300_firms: list, target_org: str) -> list:
    """Find non-G300 Firm accounts whose name starts with a G300 firm's
    suffix-stripped core name."""
    candidates = []
    cores = {}
    for f in g300_firms:
        core = strip_suffix(f["Name"])
        if len(core) >= 5:  # skip cores too short/generic to be useful
            cores.setdefault(core, []).append(f)

    core_list = sorted(cores.keys())
    for batch in chunk(core_list, 25):
        clauses = " OR ".join(f"Name LIKE '{esc(c)}%'" for c in batch)
        query = (
            f"SELECT Id, Name, Website FROM Account "
            f"WHERE RecordTypeId = '{FIRM_RECORD_TYPE_ID}' "
            f"AND G300_Account__c = false AND ({clauses})"
        )
        for rec in sf_query(query, target_org):
            for core in batch:
                if rec["Name"].startswith(core):
                    for g300 in cores[core]:
                        candidates.append({
                            "signal": "normalized_name_prefix_match",
                            "g300_id": g300["Id"], "g300_name": g300["Name"],
                            "candidate_id": rec["Id"], "candidate_name": rec["Name"],
                            "candidate_website": rec.get("Website") or "",
                        })
    return candidates


def pass4_identifier_match(g300_firms: list, target_org: str) -> list:
    """Find non-G300 Firm accounts sharing any populated unique-identifier
    field value with a G300 firm (LEI, BvD ID, ALM Account ID, etc.)."""
    candidates = []
    for field in IDENTIFIER_FIELDS:
        values_map = defaultdict(list)
        for f in g300_firms:
            v = f.get(field)
            if v:
                values_map[v].append(f)
        if not values_map:
            continue
        for batch in chunk(sorted(values_map.keys()), 60):
            in_list = ",".join(f"'{esc(v)}'" for v in batch)
            query = (
                f"SELECT Id, Name, Website, {field} FROM Account "
                f"WHERE RecordTypeId = '{FIRM_RECORD_TYPE_ID}' "
                f"AND G300_Account__c = false AND {field} IN ({in_list})"
            )
            for rec in sf_query(query, target_org):
                rec_val = rec.get(field)
                for g300 in values_map.get(rec_val, []):
                    candidates.append({
                        "signal": f"identifier_match:{field}",
                        "g300_id": g300["Id"], "g300_name": g300["Name"],
                        "candidate_id": rec["Id"], "candidate_name": rec["Name"],
                        "candidate_website": rec.get("Website") or "",
                    })
    return candidates


def pass5_completeness_gaps(g300_firms: list) -> list:
    """Flag G300 firms themselves that are missing key data - not a
    duplicate check, but 'clean' also means complete."""
    gaps = []
    for f in g300_firms:
        issues = []
        if not f.get("Website"):
            issues.append("blank_website")
        if not f.get("Model_Segmentation__c"):
            issues.append("blank_segmentation")
        offices = f.get("No_of_Offices__c")
        if offices is None or offices == 0:
            issues.append("zero_or_null_offices")
        if issues:
            gaps.append({
                "g300_id": f["Id"], "g300_name": f["Name"],
                "issues": ";".join(issues),
                "created_date": f.get("CreatedDate", ""),
            })
    return gaps


def dedupe_candidates(all_candidates: list) -> list:
    """Merge candidates found by multiple passes into one row per pair,
    combining the signals."""
    merged = {}
    for c in all_candidates:
        key = (c["g300_id"], c["candidate_id"])
        if key not in merged:
            merged[key] = dict(c)
            merged[key]["signals"] = {c["signal"]}
        else:
            merged[key]["signals"].add(c["signal"])
    rows = []
    for v in merged.values():
        v["signal"] = ", ".join(sorted(v["signals"]))
        del v["signals"]
        rows.append(v)
    rows.sort(key=lambda r: (r["g300_name"], r["candidate_name"]))
    return rows


def write_csv(path: Path, rows: list, fieldnames: list):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def main():
    parser = argparse.ArgumentParser(description="G300 Firm dedup sweep")
    parser.add_argument("--target-org", default=None,
                         help="Salesforce CLI org alias or username")
    parser.add_argument("--output-dir", default="output")
    args = parser.parse_args()

    out_dir = Path(args.output_dir)

    print("Fetching G300-flagged Firm accounts...")
    g300_firms = fetch_g300_firms(args.target_org)
    print(f"  {len(g300_firms)} G300 Firm accounts found.")
    if not g300_firms:
        print("No G300 firms found - check RecordTypeId and org connection.")
        sys.exit(1)

    print("Pass 2: website exact match...")
    p2 = pass2_website_match(g300_firms, args.target_org)
    print(f"  {len(p2)} raw hits")

    print("Pass 3: normalized full-name prefix match...")
    p3 = pass3_normalized_name_match(g300_firms, args.target_org)
    print(f"  {len(p3)} raw hits")

    print("Pass 4: cross-identifier match (LEI/BvD/ALM ID/LinkedIn/Trade Register)...")
    p4 = pass4_identifier_match(g300_firms, args.target_org)
    print(f"  {len(p4)} raw hits")

    print("Pass 5: completeness gaps on G300 records themselves...")
    p5 = pass5_completeness_gaps(g300_firms)
    print(f"  {len(p5)} G300 records with a data gap")

    all_candidates = p2 + p3 + p4
    merged = dedupe_candidates(all_candidates)

    dup_fields = ["signal", "g300_id", "g300_name", "candidate_id",
                  "candidate_name", "candidate_website"]
    write_csv(out_dir / "g300_duplicate_candidates.csv", merged, dup_fields)

    gap_fields = ["g300_id", "g300_name", "issues", "created_date"]
    write_csv(out_dir / "g300_completeness_gaps.csv", p5, gap_fields)

    summary = (
        f"G300 Dedup Sweep Summary\n"
        f"=========================\n"
        f"G300 Firm accounts checked: {len(g300_firms)}\n"
        f"Unique duplicate-candidate pairs found: {len(merged)}\n"
        f"G300 firms with >=1 duplicate candidate: "
        f"{len({r['g300_id'] for r in merged})}\n"
        f"G300 records with a completeness gap: {len(p5)}\n"
        f"\n"
        f"IMPORTANT: this is a candidate list, not a merge instruction.\n"
        f"Several patterns in this data are legacy predecessor-firm names\n"
        f"(e.g. a firm that renamed or merged years ago) that may be\n"
        f"intentional historical records rather than true duplicates -\n"
        f"review each row before merging. Confirm merge direction manually\n"
        f"per record, per the CE-master lesson from the 24 Sep run.\n"
    )
    (out_dir / "g300_sweep_summary.txt").write_text(summary)
    print("\n" + summary)
    print(f"Full results written to {out_dir}/")


if __name__ == "__main__":
    main()
