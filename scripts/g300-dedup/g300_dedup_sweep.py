#!/usr/bin/env python3
"""
G300 Firm Account Dedup Sweep
==============================

Identifies candidate duplicate Account records (RecordType = Firm) for the
302 accounts flagged G300_Account__c = true, using independent signals:

  Pass 2 - Website match on the normalized domain (scheme, www., trailing
           slash, path and case ignored)
  Pass 3 - Normalized name match (legal suffixes stripped; punctuation,
           spacing, "&"/"and", case and accents ignored), plus known former
           names from g300_aliases.csv. A candidate matches when its core
           equals the G300 core, extends it ("Dechert Kazakhstan"), or is a
           short form of it ("Gibson Dunn", "Ogletree").
  Pass 4 - Cross-reference on other unique identifiers (LEI, BvD ID, Orbis
           ID, ALM Account ID, LinkedIn Company ID, Trade Register Number)
  Pass 5 - Structural / completeness gaps on the G300 records themselves
           (zero offices, blank website, blank segmentation, G300 flag on a
           non-Firm record)
  Pass 6 - Duplicates inside the G300 set itself (two flagged records for
           the same firm), on the same signals as Passes 2-4

This is a READ-ONLY identification pass. It does NOT merge or write anything.
Output is two CSVs for manual review before any merge is executed - per the
CE-master lesson from 24 Sep, merge direction must be confirmed by a human,
not inferred by this script. The candidate CSV carries the evidence a human
needs for that call (created date/by, child offices, contacts and
opportunities across each record's office hierarchy) but deliberately
makes no survivor choice.

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
import unicodedata
from collections import Counter, defaultdict
from itertools import combinations
from pathlib import Path

FIRM_RECORD_TYPE_ID = "0126g000000OhUSAA0"

# Fields used for the cross-identifier check (Pass 4). Add/remove as your
# org's data quality on these fields changes over time. SF_ALM_ID__c is
# deliberately absent: it is an Auto Number, unique per record by
# construction, so it can never match another record.
IDENTIFIER_FIELDS = [
    "LEI_Legal_Entity_Identifier__c",
    "BvD_ID_Number__c",
    "Orbis_ID__c",
    "ALM_Account_ID__c",
    "LID__LinkedIn_Company_Id__c",
    "Trade_Register_Number__c",
]

BASE_FIELDS = [
    "Id", "Name", "Website", "No_of_Offices__c", "Model_Segmentation__c",
    "CreatedDate", "CreatedBy.Name",
] + IDENTIFIER_FIELDS

CANDIDATE_FIELDS = ["Id", "Name", "Website", "CreatedDate", "CreatedBy.Name"]

DEFAULT_ALIASES = Path(__file__).with_name("g300_aliases.csv")

# `sf data query` sends the SOQL in the REST query string, so long IN/OR
# lists fail with "URI too long". Batches are sized by characters, not
# item count, to stay well clear of that once URL-encoded.
MAX_CLAUSE_CHARS = 4000

# Name-match queries LIKE on the leading core tokens - at least this many,
# and more until they hold MIN_LIKE_CHARS letters, so initials like "K&L"
# don't become 'K%L%' (which matches ~18k Firm names). The precise
# comparison happens in Python afterwards.
LIKE_PREFIX_TOKENS = 2
MIN_LIKE_CHARS = 6

# One-word short forms ("Ogletree" for "Ogletree, Deakins, Nash, ...") are
# fetched by exact name, with these endings, when the word is at least
# SHORT_FORM_MIN_CHARS long. Endings like "Law Firm" or "PC" are left out:
# "Baker Law Firm" is the usual shape of an unrelated one-person firm.
SHORT_FORM_MIN_CHARS = 4
SHORT_FORM_ENDINGS = ("", " LLP", ", LLP")

WEBSITE_PREFIXES = ("", "www.", "http://", "https://", "http://www.", "https://www.")

SUFFIX_RE = re.compile(
    r'\s*[,]?\s*\b(L\.?L\.?P\.?|L\.?L\.?C\.?|P\.?L\.?L\.?C\.?|P\.?L\.?C\.?|'
    r'P\.?C\.?|P\.?A\.?|L\.?P\.?|LPC|N\.?V\.?|S\.?L\.?P\.?|GmbH.*|'
    r'Professional Corporation|Verein|Limited|Ltd\.?|Inc\.?|Et\.? Al\.?|'
    r'(?:PartG )?mbB|Partnerschaftsgesellschaft|Partnerschaft von Rechtsanw\w+|'
    r'Rechtsanw\w+|Abogados|Advogados(?: Associados)?|SELAS|Soci\w+ d.Avocats|'
    r'Law Firm|Law Offices?|Law Group|Lawyers|Legal)\s*\.?\s*$',
    re.IGNORECASE,
)

TOKEN_RE = re.compile(r"[^\W_]+")
CAMEL_RE = re.compile(r"(?<=[a-z])(?=[A-Z])")
# Name prefixes that are not word boundaries ("McGuire", "DeHeng").
CAMEL_KEEP = {"mc", "mac", "de", "di", "da", "la", "le", "van", "von", "o"}


class QueryError(RuntimeError):
    """A SOQL query failed or came back incomplete."""


def strip_suffix(name: str) -> str:
    """Iteratively strip trailing legal-entity suffixes to get a comparable core name."""
    prev, n = None, name.strip()
    while prev != n:
        prev = n
        n = SUFFIX_RE.sub('', n).strip().rstrip(',').strip()
    return n


def fold_accents(s: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFKD", s)
                   if not unicodedata.combining(c))


def camel_split(token: str) -> list:
    """'McGuireWoods' -> ['McGuire', 'Woods'], 'ArentFox' -> ['Arent', 'Fox'];
    left whole when a part would be under 3 letters ('JunHe')."""
    parts, cur = [], ""
    for piece in CAMEL_RE.split(token):
        cur += piece
        if cur.casefold() not in CAMEL_KEEP:
            parts.append(cur)
            cur = ""
    if cur:
        parts.append(cur)
    return parts if all(len(p) >= 3 for p in parts) else [token]


def raw_tokens(name: str) -> list:
    """Word tokens in their original spelling, without the connective 'and'."""
    return [t for t in TOKEN_RE.findall(name) if t.casefold() != "and"]


def name_key(name: str) -> tuple:
    """Comparable token tuple for a firm name: suffix-stripped, accent- and
    case-folded, punctuation, spacing inside compound brands and
    '&'/'and' ignored."""
    return tuple(fold_accents(p).casefold()
                 for t in raw_tokens(strip_suffix(name)) for p in camel_split(t))


def normalize_domain(website: str) -> str:
    """'HTTPS://www.Dechert.com/en/' -> 'dechert.com'."""
    s = (website or "").strip().lower()
    s = re.sub(r"^[a-z][a-z0-9+.\-]*://", "", s)
    s = re.split(r"[/?#]", s, maxsplit=1)[0]
    s = s.rsplit("@", 1)[-1].split(":", 1)[0].strip(".")
    if s.startswith("www."):
        s = s[4:]
    return s


def website_variants(domain: str) -> list:
    return [p + domain + s for p in WEBSITE_PREFIXES for s in ("", "/")]


def norm_value(v) -> str:
    return str(v).strip().casefold() if v is not None else ""


def get_path(rec: dict, path: str):
    """Read a possibly-dotted field ('CreatedBy.Name') from a query record."""
    cur = rec
    for part in path.split("."):
        if not isinstance(cur, dict):
            return None
        cur = cur.get(part)
    return cur


def sf_query(query: str, target_org: str) -> list:
    """Run a SOQL query via the Salesforce CLI and return every record.

    Raises QueryError rather than returning [] on failure: an empty list
    from a failed batch would read as "no duplicates" in the output.
    """
    cmd = ["sf", "data", "query", "--query", query, "--json"]
    if target_org:
        cmd += ["--target-org", target_org]
    result = subprocess.run(cmd, capture_output=True, text=True)
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError:
        payload = None
    if result.returncode != 0 or not payload or payload.get("status") != 0:
        # With --json the CLI writes its error object to stdout, not stderr.
        detail = (payload or {}).get("message") or result.stderr or result.stdout
        raise QueryError(f"Query failed:\n{query}\n{detail}")
    res = payload.get("result", {})
    records = res.get("records", [])
    total = res.get("totalSize")
    if total is not None and total > len(records):
        raise QueryError(
            f"Query returned {len(records)} of {total} records (CLI fetch "
            f"limit - raise org-max-query-limit):\n{query}")
    return records


def esc(s: str) -> str:
    return s.replace("\\", "\\\\").replace("'", "\\'")


def chunk_by_chars(items, max_chars=MAX_CLAUSE_CHARS):
    """Split rendered clause fragments into batches of bounded total length."""
    batch, size = [], 0
    for item in items:
        if batch and size + len(item) + 4 > max_chars:
            yield batch
            batch, size = [], 0
        batch.append(item)
        size += len(item) + 4
    if batch:
        yield batch


def in_list(values) -> list:
    return [f"'{esc(v)}'" for v in values]


def candidate_query(extra_fields, where: str) -> str:
    fields = ", ".join(dict.fromkeys(CANDIDATE_FIELDS + list(extra_fields)))
    return (
        f"SELECT {fields} FROM Account "
        f"WHERE RecordTypeId = '{FIRM_RECORD_TYPE_ID}' "
        f"AND G300_Account__c = false AND ({where})"
    )


def candidate_row(signal: str, g300: dict, rec: dict) -> dict:
    return {
        "signal": signal,
        "g300_id": g300["Id"], "g300_name": g300["Name"],
        "g300_website": g300.get("Website") or "",
        "g300_created": g300.get("CreatedDate") or "",
        "candidate_id": rec["Id"], "candidate_name": rec["Name"],
        "candidate_website": rec.get("Website") or "",
        "candidate_created": rec.get("CreatedDate") or "",
        "candidate_created_by": get_path(rec, "CreatedBy.Name") or "",
    }


def load_aliases(path, g300_firms: list) -> dict:
    """{g300_id: [former name, ...]} from a g300_id,alias,note CSV. Rows for
    Ids outside the fetched G300 set are reported and ignored."""
    aliases = defaultdict(list)
    if not path or not Path(path).exists():
        return aliases
    known = {f["Id"] for f in g300_firms}
    with open(path, newline="", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            gid, alias = (row.get("g300_id") or "").strip(), (row.get("alias") or "").strip()
            if not gid or not alias:
                continue
            if gid not in known:
                print(f"  [warn] alias '{alias}' names {gid}, not a G300 Firm - ignored")
                continue
            aliases[gid].append(alias)
    return aliases


def fetch_g300_firms(target_org: str) -> list:
    fields = ", ".join(BASE_FIELDS)
    query = (
        f"SELECT {fields} FROM Account "
        f"WHERE RecordTypeId = '{FIRM_RECORD_TYPE_ID}' "
        f"AND G300_Account__c = true ORDER BY Name, Id"
    )
    return sf_query(query, target_org)


def fetch_g300_non_firm(target_org: str) -> list:
    query = (
        "SELECT Id, Name, RecordType.Name, CreatedDate FROM Account "
        f"WHERE G300_Account__c = true AND RecordTypeId != '{FIRM_RECORD_TYPE_ID}' "
        "ORDER BY Name, Id"
    )
    return sf_query(query, target_org)


def pass2_website_match(g300_firms: list, target_org: str) -> list:
    """Find non-G300 Firm accounts whose Website is the same domain as a
    G300 firm's, whatever the scheme/www./trailing-slash/case."""
    candidates = []
    by_domain = defaultdict(list)
    for f in g300_firms:
        d = normalize_domain(f.get("Website"))
        if d:
            by_domain[d].append(f)

    variants = [v for d in sorted(by_domain) for v in website_variants(d)]
    for batch in chunk_by_chars(in_list(variants)):
        query = candidate_query([], f"Website IN ({','.join(batch)})")
        for rec in sf_query(query, target_org):
            for g300 in by_domain.get(normalize_domain(rec.get("Website")), []):
                candidates.append(candidate_row("website_domain_match", g300, rec))
    return candidates


def name_match_kind(g300_key: tuple, cand_key: tuple):
    """How a candidate core relates to a G300 core:
    'exact'      - same tokens, or same letters once spacing is ignored
                   ("McGuire Woods" / "McGuireWoods")
    'extends'    - the candidate adds words ("Dechert Kazakhstan")
    'short_form' - the candidate is the leading part ("Gibson Dunn",
                   "Ogletree"); one-word short forms need
                   SHORT_FORM_MIN_CHARS letters so "Fox" never matches.
    None otherwise."""
    if not g300_key or not cand_key:
        return None
    if cand_key == g300_key or "".join(cand_key) == "".join(g300_key):
        return "exact"
    if cand_key[:len(g300_key)] == g300_key:
        return "extends"
    if g300_key[:len(cand_key)] == cand_key and (
            len(cand_key) >= 2 or len(cand_key[0]) >= SHORT_FORM_MIN_CHARS):
        return "short_form"
    return None


def like_tokens(name: str) -> list:
    """Leading tokens to LIKE on: the suffix-stripped core, compound brands
    split ('McGuire%Woods%' also finds 'McGuire Woods'), extended - into the
    stripped suffix words if need be ('V&T Law Firm' -> V, T, Law, Firm) -
    until the pattern is specific enough."""
    base = raw_tokens(strip_suffix(name))
    pool = base + raw_tokens(name)[len(base):]
    toks = []
    for i, t in enumerate(pool):
        if toks:
            # Suffix words are only borrowed to pad out bare initials.
            if i >= len(base) and min(map(len, toks)) >= 3:
                break
            if len(toks) >= LIKE_PREFIX_TOKENS and sum(map(len, toks)) >= MIN_LIKE_CHARS:
                break
        toks.extend(camel_split(t))
    return toks


def like_patterns(name: str) -> list:
    """SOQL LIKE patterns on the leading core tokens, joined by '%' so any
    punctuation or '&'/'and' between them matches. LIKE is case-insensitive
    but accent-sensitive, so an accent-folded pattern is added when it
    differs."""
    toks = like_tokens(name)
    if not toks:
        return []
    pats = {"%".join(toks) + "%", "%".join(fold_accents(t) for t in toks) + "%"}
    return sorted(pats)


def short_form_names(name: str) -> list:
    """Exact names a one-word short form of this firm would carry
    ("Ogletree", "Ogletree LLP", ...). Only for multi-word cores - a
    one-word core is already covered by its LIKE pattern."""
    base = raw_tokens(strip_suffix(name))
    if len(base) < 2 or len(base[0]) < SHORT_FORM_MIN_CHARS:
        return []
    words = {base[0], fold_accents(base[0])}
    return sorted(w + e for w in words for e in SHORT_FORM_ENDINGS)


def name_entries(g300_firms: list, aliases: dict) -> list:
    """(label, text, key, g300) for every G300 name and every alias."""
    entries = []
    for f in g300_firms:
        entries.append(("name", f["Name"], name_key(f["Name"]), f))
        for a in aliases.get(f["Id"], []):
            entries.append(("alias", a, name_key(a), f))
    return entries


def pass3_normalized_name_match(g300_firms: list, target_org: str, aliases=None):
    """Find non-G300 Firm accounts whose normalized core name equals,
    extends, or is a short form of a G300 firm's core name or one of its
    known former names. Returns (candidates, skipped) where skipped lists
    names with no usable core."""
    candidates, skipped = [], []
    entries, like, exact = [], set(), set()
    # A one-word short form is only attributable when that word starts the
    # name (or a former name) of a single G300 firm: "Davis" could be Davis
    # Polk or Davis Wright Tremaine, so it is not reported for either.
    owners = defaultdict(set)
    for _, _, key, f in name_entries(g300_firms, aliases or {}):
        if key:
            owners[key[0]].add(f["Id"])
    for label, text, key, f in name_entries(g300_firms, aliases or {}):
        pats = like_patterns(text)
        # A single short token (e.g. "CMS") is too generic to LIKE on
        # safely; report it rather than dropping it silently.
        if not key or not pats or (len(key) == 1 and len(key[0]) < 3):
            skipped.append(text)
            continue
        entries.append((label, key, f))
        like.update(pats)
        exact.update(short_form_names(text))

    clauses = [f"Name LIKE '{esc(p)}'" for p in sorted(like)]
    queries = [" OR ".join(b) for b in chunk_by_chars(clauses)]
    queries += [f"Name IN ({','.join(b)})" for b in chunk_by_chars(in_list(sorted(exact)))]
    seen = set()
    for where in queries:
        for rec in sf_query(candidate_query([], where), target_org):
            if rec["Id"] in seen:
                continue
            seen.add(rec["Id"])
            cand_key = name_key(rec["Name"])
            ambiguous = len(cand_key) == 1 and len(owners.get(cand_key[0], ())) > 1
            for label, key, g300 in entries:
                kind = name_match_kind(key, cand_key)
                if kind == "short_form" and ambiguous:
                    continue
                if kind:
                    candidates.append(candidate_row(f"{label}_{kind}", g300, rec))
    return candidates, skipped


def pass4_identifier_match(g300_firms: list, target_org: str) -> list:
    """Find non-G300 Firm accounts sharing any populated unique-identifier
    field value with a G300 firm (LEI, BvD ID, ALM Account ID, etc.)."""
    candidates = []
    for field in IDENTIFIER_FIELDS:
        values_map = defaultdict(list)
        raw_values = {}
        for f in g300_firms:
            v = norm_value(f.get(field))
            if v:
                values_map[v].append(f)
                raw_values.setdefault(v, str(f[field]).strip())
        if not values_map:
            continue
        for batch in chunk_by_chars(in_list(sorted(raw_values.values()))):
            query = candidate_query([field], f"{field} IN ({','.join(batch)})")
            for rec in sf_query(query, target_org):
                for g300 in values_map.get(norm_value(rec.get(field)), []):
                    candidates.append(candidate_row(
                        f"identifier_match:{field}", g300, rec))
    return candidates


def pass5_completeness_gaps(g300_firms: list, non_firm: list, office_counts: dict) -> list:
    """Flag G300 records themselves that are missing key data - not a
    duplicate check, but 'clean' also means complete. office_counts is
    the real number of child Office records per G300 Id, which
    No_of_Offices__c is supposed to hold but often lags."""
    gaps = []
    for f in g300_firms:
        issues = []
        if not f.get("Website"):
            issues.append("blank_website")
        if not f.get("Model_Segmentation__c"):
            issues.append("blank_segmentation")
        offices = f.get("No_of_Offices__c")
        actual = office_counts.get(f["Id"], 0)
        if offices is None or offices == 0:
            issues.append("zero_or_null_offices")
        if actual == 0:
            issues.append("no_child_office_records")
        elif offices is not None and int(offices) != actual:
            issues.append(f"office_count_stale:field={int(offices)},actual={actual}")
        if issues:
            gaps.append({
                "g300_id": f["Id"], "g300_name": f["Name"],
                "issues": ";".join(issues),
                "created_date": f.get("CreatedDate", ""),
            })
    for r in non_firm:
        rt = get_path(r, "RecordType.Name") or "no_record_type"
        gaps.append({
            "g300_id": r["Id"], "g300_name": r["Name"],
            "issues": f"g300_flag_on_non_firm_record:{rt}",
            "created_date": r.get("CreatedDate", ""),
        })
    return gaps


def pass6_within_g300(g300_firms: list, aliases=None) -> list:
    """Pairs of G300-flagged Firm records that look like the same firm.
    Passes 2-4 only ever look at non-G300 records, so these would
    otherwise never surface."""
    keys = defaultdict(list)
    for label, _, key, f in name_entries(g300_firms, aliases or {}):
        keys[f["Id"]].append((label, key))
    candidates = []
    for a, b in combinations(sorted(g300_firms, key=lambda r: r["Id"]), 2):
        signals = set()
        da, db = normalize_domain(a.get("Website")), normalize_domain(b.get("Website"))
        if da and da == db:
            signals.add("website_domain_match")
        for x, y in ((a, b), (b, a)):
            y_key = name_key(y["Name"])
            for label, key in keys[x["Id"]]:
                kind = name_match_kind(key, y_key)
                if kind:
                    signals.add(f"{label}_{kind}")
        for field in IDENTIFIER_FIELDS:
            va, vb = norm_value(a.get(field)), norm_value(b.get(field))
            if va and va == vb:
                signals.add(f"identifier_match:{field}")
        for s in sorted(signals):
            candidates.append(candidate_row(f"within_g300:{s}", a, b))
    return candidates


def match_tier(signals) -> int:
    """1 = exact name/alias core, 2 = short form or extension of one,
    3 = website/identifier only. Rank on this, not on signal count: the
    bulk-load duplicates have no website or identifiers, so they can only
    ever score one signal, while a person record carrying the firm's
    website scores two."""
    names = [s.split(":")[-1] for s in signals if "website" not in s and "identifier" not in s]
    if any(n.endswith("_exact") for n in names):
        return 1
    return 2 if names else 3


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
        v["signal_count"] = len(v["signals"])
        v["tier"] = match_tier(v["signals"])
        del v["signals"]
        rows.append(v)
    rows.sort(key=lambda r: (r["tier"], r["g300_name"], r["candidate_name"], r["candidate_id"]))
    return rows


def count_by(object_name: str, group_field: str, ids: list, target_org: str) -> dict:
    counts = {}
    for batch in chunk_by_chars(in_list(ids)):
        query = (
            f"SELECT {group_field} k, COUNT(Id) n FROM {object_name} "
            f"WHERE {group_field} IN ({','.join(batch)}) GROUP BY {group_field}"
        )
        for rec in sf_query(query, target_org):
            counts[rec["k"]] = rec["n"]
    return counts


def hierarchy_count(object_name: str, ids: list, target_org: str) -> dict:
    """Records on the account itself plus on its Office records - in this
    org contacts and opportunities mostly sit on Offices, not the Firm."""
    direct = count_by(object_name, "AccountId", ids, target_org)
    via_offices = count_by(object_name, "Account.Ultimate_Account__c", ids, target_org)
    return {i: direct.get(i, 0) + via_offices.get(i, 0) for i in ids}


def add_triage_evidence(rows: list, target_org: str) -> None:
    """Attach the facts a human needs to choose merge direction: child
    Office records (which a merge must re-parent), contacts and
    opportunities across each record's hierarchy, and which record is
    older. No survivor is chosen here."""
    ids = sorted({r["g300_id"] for r in rows} | {r["candidate_id"] for r in rows})
    if not ids:
        return
    offices = count_by("Account", "Ultimate_Account__c", ids, target_org)
    contacts = hierarchy_count("Contact", ids, target_org)
    opps = hierarchy_count("Opportunity", ids, target_org)
    for r in rows:
        for side in ("g300", "candidate"):
            rid = r[f"{side}_id"]
            r[f"{side}_child_offices"] = offices.get(rid, 0)
            r[f"{side}_contacts"] = contacts.get(rid, 0)
            r[f"{side}_opportunities"] = opps.get(rid, 0)
        older = (r["candidate_created"] and r["g300_created"]
                 and r["candidate_created"] < r["g300_created"])
        r["candidate_is_older"] = "Y" if older else "N"


def write_csv(path: Path, rows: list, fieldnames: list):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


DUP_FIELDS = [
    "tier", "signal", "signal_count",
    "g300_id", "g300_name", "g300_website", "g300_created",
    "g300_child_offices", "g300_contacts", "g300_opportunities",
    "candidate_id", "candidate_name", "candidate_website",
    "candidate_created", "candidate_created_by", "candidate_is_older",
    "candidate_child_offices", "candidate_contacts", "candidate_opportunities",
]
GAP_FIELDS = ["g300_id", "g300_name", "issues", "created_date"]


def main():
    parser = argparse.ArgumentParser(description="G300 Firm dedup sweep")
    parser.add_argument("--target-org", default=None,
                        help="Salesforce CLI org alias or username")
    parser.add_argument("--output-dir", default="output")
    parser.add_argument("--aliases", default=str(DEFAULT_ALIASES),
                        help="CSV of g300_id,alias,note former names ('' to skip)")
    args = parser.parse_args()

    out_dir = Path(args.output_dir)

    print("Fetching G300-flagged Firm accounts...")
    g300_firms = fetch_g300_firms(args.target_org)
    print(f"  {len(g300_firms)} G300 Firm accounts found.")
    if not g300_firms:
        print("No G300 firms found - check RecordTypeId and org connection.")
        sys.exit(1)
    aliases = load_aliases(args.aliases, g300_firms)
    print(f"  {sum(map(len, aliases.values()))} former names loaded for "
          f"{len(aliases)} firms.")

    print("Pass 2: website domain match...")
    p2 = pass2_website_match(g300_firms, args.target_org)
    print(f"  {len(p2)} raw hits")

    print("Pass 3: normalized name match (incl. short forms and former names)...")
    p3, skipped = pass3_normalized_name_match(g300_firms, args.target_org, aliases)
    print(f"  {len(p3)} raw hits")
    if skipped:
        print(f"  {len(skipped)} name(s) too short/generic to name-match: "
              + "; ".join(skipped))

    print("Pass 4: cross-identifier match (LEI/BvD/Orbis/ALM ID/LinkedIn/Trade Register)...")
    p4 = pass4_identifier_match(g300_firms, args.target_org)
    print(f"  {len(p4)} raw hits")

    print("Pass 5: completeness gaps on G300 records themselves...")
    non_firm = fetch_g300_non_firm(args.target_org)
    office_counts = count_by("Account", "Ultimate_Account__c",
                             sorted(f["Id"] for f in g300_firms), args.target_org)
    p5 = pass5_completeness_gaps(g300_firms, non_firm, office_counts)
    print(f"  {len(p5)} G300 records with a data gap")

    print("Pass 6: duplicates within the G300 set...")
    p6 = pass6_within_g300(g300_firms, aliases)
    print(f"  {len(p6)} raw hits")

    merged = dedupe_candidates(p2 + p3 + p4 + p6)

    print("Collecting triage evidence (child offices, contacts, opportunities)...")
    add_triage_evidence(merged, args.target_org)

    write_csv(out_dir / "g300_duplicate_candidates.csv", merged, DUP_FIELDS)
    write_csv(out_dir / "g300_completeness_gaps.csv", p5, GAP_FIELDS)

    signal_counts = Counter(s for r in merged for s in r["signal"].split(", "))
    external = [r for r in merged if not r["signal"].startswith("within_g300")]
    within = [r for r in merged if r["signal"].startswith("within_g300")]
    batches = Counter((r["candidate_created"][:10], r["candidate_created_by"])
                      for r in external)

    summary = (
        f"G300 Dedup Sweep Summary\n"
        f"=========================\n"
        f"G300 Firm accounts checked: {len(g300_firms)}\n"
        f"Former names (aliases) used: {sum(map(len, aliases.values()))}\n"
        f"Unique duplicate-candidate pairs found: {len(merged)}\n"
        f"  vs non-G300 Firm records: {len(external)} pairs, "
        f"{len({r['candidate_id'] for r in external})} distinct candidate records\n"
        f"  within the G300 set: {len(within)} pairs\n"
        f"  tier 1 (exact name/alias): {sum(1 for r in merged if r['tier'] == 1)}\n"
        f"  tier 2 (short form / extension): {sum(1 for r in merged if r['tier'] == 2)}\n"
        f"  tier 3 (website/identifier only): {sum(1 for r in merged if r['tier'] == 3)}\n"
        f"G300 firms with >=1 duplicate candidate: "
        f"{len({r['g300_id'] for r in merged})}\n"
        f"G300 records with a completeness gap: {len(p5)}\n"
        f"Names not name-matched (too short/generic): {len(skipped)}"
        + (f" - {'; '.join(skipped)}" if skipped else "") + "\n"
        f"\n"
        f"Pairs per signal:\n"
        + "".join(f"  {s}: {n}\n" for s, n in sorted(signal_counts.items()))
        + f"\n"
        f"Candidates by creation date and creator (top 10):\n"
        + "".join(f"  {d} {who or '?'}: {n}\n" for (d, who), n in batches.most_common(10))
        + f"\n"
        f"IMPORTANT: this is a candidate list, not a merge instruction.\n"
        f"Several patterns in this data are legacy predecessor-firm names\n"
        f"(e.g. a firm that renamed or merged years ago) that may be\n"
        f"intentional historical records rather than true duplicates -\n"
        f"review each row before merging. Website-only matches are often\n"
        f"people or unrelated organisations carrying the firm's domain.\n"
        f"Confirm merge direction manually per record, per the CE-master\n"
        f"lesson from the 24 Sep run.\n"
    )
    (out_dir / "g300_sweep_summary.txt").write_text(summary)
    print("\n" + summary)
    print(f"Full results written to {out_dir}/")


if __name__ == "__main__":
    try:
        main()
    except QueryError as e:
        print(f"[ERROR] {e}", file=sys.stderr)
        sys.exit(2)
