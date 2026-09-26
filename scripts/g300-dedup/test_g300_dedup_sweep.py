#!/usr/bin/env python3
"""Unit tests for g300_dedup_sweep.py. No org needed: sf_query is replaced
by a fake that answers from canned records.

    python3 -m unittest discover -s scripts/g300-dedup
"""
import csv
import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import g300_dedup_sweep as s  # noqa: E402

QUOTED = r"'((?:[^'\\]|\\.)*)'"


def firm(id_, name, website=None, **kw):
    rec = {"Id": id_, "Name": name, "Website": website,
           "No_of_Offices__c": 5, "Model_Segmentation__c": "A",
           "CreatedDate": "2021-01-20T19:40:56.000+0000",
           "CreatedBy": {"Name": "Loader"}}
    rec.update(kw)
    return rec


def unescape(v):
    return v.replace("\\'", "'").replace("\\\\", "\\")


class FakeOrg:
    """Evaluates the WHERE shapes the sweep generates (Website IN, Name LIKE,
    Name IN, <identifier> IN) against canned records, case-insensitively
    like SOQL. LIKE stays accent-sensitive, as it is in Production."""

    def __init__(self, records):
        self.records = records
        self.queries = []

    def __call__(self, query, target_org):
        self.queries.append(query)
        return [r for r in self.records if self.matches(query, r)]

    @staticmethod
    def values_after(query, marker):
        return {unescape(v).lower()
                for v in re.findall(QUOTED, query.split(marker, 1)[1].split(")", 1)[0])}

    def matches(self, q, rec):
        if "Website IN (" in q:
            return (rec.get("Website") or "").lower() in self.values_after(q, "Website IN (")
        if "Name IN (" in q:
            return rec["Name"].lower() in self.values_after(q, "Name IN (")
        if "Name LIKE" in q:
            for p in re.findall(r"Name LIKE " + QUOTED, q):
                rx = "^" + ".*".join(re.escape(x) for x in unescape(p).split("%")) + "$"
                if re.match(rx, rec["Name"], re.IGNORECASE | re.DOTALL):
                    return True
            return False
        for field in s.IDENTIFIER_FIELDS:
            if f"{field} IN (" in q:
                v = rec.get(field)
                return v is not None and str(v).lower() in self.values_after(q, f"{field} IN (")
        return False


class NormalizationTests(unittest.TestCase):
    def test_strip_suffix(self):
        self.assertEqual(s.strip_suffix("Ballard Spahr LLP"), "Ballard Spahr")
        self.assertEqual(s.strip_suffix("Freeman Mathis & Gary, LLP"), "Freeman Mathis & Gary")
        self.assertEqual(s.strip_suffix("Uría Menéndez Abogados, S.L.P."), "Uría Menéndez")
        self.assertEqual(s.strip_suffix("Knights Professional Services Limited"),
                         "Knights Professional Services")
        self.assertEqual(s.strip_suffix("Wilson Sonsini Goodrich Et Al"), "Wilson Sonsini Goodrich")
        self.assertEqual(s.strip_suffix("Hengeler Mueller Partnerschaft von Rechtsanwälten mbB"),
                         "Hengeler Mueller")
        self.assertEqual(s.strip_suffix("V&T Law Firm"), "V&T")
        self.assertEqual(s.strip_suffix("Smith Lopa"), "Smith Lopa")   # no mid-word strip

    def test_name_key_ignores_case_punctuation_ampersand_accents_spacing(self):
        k = s.name_key("Skadden, Arps, Slate, Meagher & Flom LLP")
        self.assertEqual(k, s.name_key("SKADDEN ARPS SLATE MEAGHER AND FLOM"))
        self.assertEqual(s.name_key("Uría Menéndez"), ("uria", "menendez"))
        self.assertEqual(s.name_key("K&L Gates LLP"), ("k", "l", "gates"))
        self.assertEqual(s.name_key("McGuireWoods LLP"), s.name_key("McGuire Woods"))
        self.assertEqual(s.name_key("McDermott Will & Schulte"), ("mcdermott", "will", "schulte"))

    def test_camel_split(self):
        self.assertEqual(s.camel_split("McGuireWoods"), ["McGuire", "Woods"])
        self.assertEqual(s.camel_split("ArentFox"), ["Arent", "Fox"])
        self.assertEqual(s.camel_split("JunHe"), ["JunHe"])
        self.assertEqual(s.camel_split("McDermott"), ["McDermott"])
        self.assertEqual(s.camel_split("DLA"), ["DLA"])

    def test_normalize_domain(self):
        for w in ["www.dechert.com", "dechert.com", "HTTPS://WWW.Dechert.com/",
                  "http://dechert.com/en/offices?x=1", "https://www.dechert.com:443"]:
            self.assertEqual(s.normalize_domain(w), "dechert.com", w)
        self.assertEqual(s.normalize_domain("sg.rajahtannasia.com"), "sg.rajahtannasia.com")
        self.assertEqual(s.normalize_domain(None), "")

    def test_name_match_kind(self):
        k = s.name_key
        g = k("Paul, Weiss, Rifkind, Wharton & Garrison LLP")
        self.assertEqual(s.name_match_kind(g, k("Paul Weiss")), "short_form")
        self.assertIsNone(s.name_match_kind(g, k("Pau")))
        self.assertEqual(s.name_match_kind(k("Ogletree, Deakins, Nash, Smoak & Stewart, P.C."),
                                           k("Ogletree")), "short_form")
        self.assertIsNone(s.name_match_kind(k("Fox Rothschild LLP"), k("Fox")))
        self.assertEqual(s.name_match_kind(k("Dechert LLP"), k("DECHERT")), "exact")
        self.assertEqual(s.name_match_kind(k("Dechert LLP"), k("Dechert (Luxembourg) LLP")), "extends")
        self.assertEqual(s.name_match_kind(k("V&T Law Firm"), k("VT")), "exact")
        self.assertIsNone(s.name_match_kind(k("K&L Gates"), k("Kirkpatrick & Lockhart")))
        self.assertIsNone(s.name_match_kind(k("Dechert"), k("Dechertson Holdings")))

    def test_like_patterns(self):
        self.assertEqual(s.like_patterns("Uría Menéndez Abogados, S.L.P."),
                         ["Uria%Menendez%", "Uría%Menéndez%"])
        self.assertEqual(s.like_patterns("Debevoise & Plimpton LLP"), ["Debevoise%Plimpton%"])
        self.assertEqual(s.like_patterns("Dechert LLP"), ["Dechert%"])
        self.assertEqual(s.like_patterns("DWF LLP"), ["DWF%"])
        self.assertEqual(s.like_patterns("McGuireWoods LLP"), ["McGuire%Woods%"])

    def test_like_patterns_extend_past_initials(self):
        self.assertEqual(s.like_patterns("K&L Gates LLP"), ["K%L%Gates%"])
        self.assertEqual(s.like_patterns("J&A Garrigues, S.L.P."), ["J%A%Garrigues%"])
        self.assertEqual(s.like_patterns("V&T Law Firm"), ["V%T%Law%Firm%"])
        self.assertEqual(s.like_patterns("Lee & Ko"), ["Lee%Ko%"])

    def test_short_form_names(self):
        names = s.short_form_names("Ogletree, Deakins, Nash, Smoak & Stewart, P.C.")
        self.assertIn("Ogletree", names)
        self.assertIn("Ogletree LLP", names)
        self.assertEqual(s.short_form_names("Dechert LLP"), [])        # one-word core
        self.assertEqual(s.short_form_names("Fox Rothschild LLP"), [])  # word too short

    def test_chunk_by_chars_bounds_batches(self):
        items = [f"'{i:04d}xxxxxxxxxxxxxxxx'" for i in range(1000)]
        batches = list(s.chunk_by_chars(items, 500))
        self.assertEqual(sum(len(b) for b in batches), 1000)
        self.assertTrue(all(len(",".join(b)) <= 500 for b in batches))


class SfQueryTests(unittest.TestCase):
    def run_with(self, returncode, stdout, stderr=""):
        done = subprocess.CompletedProcess([], returncode, stdout=stdout, stderr=stderr)
        with mock.patch.object(s.subprocess, "run", return_value=done):
            return s.sf_query("SELECT Id FROM Account", "alias")

    def test_failure_raises_instead_of_returning_empty(self):
        with self.assertRaises(s.QueryError) as cm:
            self.run_with(1, json.dumps({"status": 1, "message": "INVALID_FIELD"}))
        self.assertIn("INVALID_FIELD", str(cm.exception))
        with self.assertRaises(s.QueryError):
            self.run_with(1, "", "sf: command not found")

    def test_truncated_result_raises(self):
        body = {"status": 0, "result": {"totalSize": 3, "records": [{"Id": "1"}]}}
        with self.assertRaises(s.QueryError):
            self.run_with(0, json.dumps(body))

    def test_success(self):
        body = {"status": 0, "result": {"totalSize": 1, "records": [{"Id": "1"}]}}
        self.assertEqual(self.run_with(0, json.dumps(body)), [{"Id": "1"}])


class PassTests(unittest.TestCase):
    def setUp(self):
        self.g300 = [
            firm("G1", "Dechert LLP", "www.dechert.com", ALM_Account_ID__c="0013600000RQKUKAA5"),
            firm("G2", "Debevoise & Plimpton LLP", "www.debevoise.com"),
            firm("G3", "Uría Menéndez Abogados, S.L.P."),
            firm("G4", "Ogletree, Deakins, Nash, Smoak & Stewart, P.C.", "www.ogletree.com"),
            firm("G5", "McDermott Will & Schulte LLP", "www.mwe.com"),
            firm("G6", "McGuireWoods LLP", "www.mcguirewoods.com"),
            firm("G7", "Davis Polk & Wardwell LLP", "www.davispolk.com"),
            firm("G8", "Davis Wright Tremaine LLP", "www.dwt.com"),
        ]

    def test_pass2_matches_domain_variants_and_case(self):
        org = FakeOrg([firm("C1", "Dechert", "HTTPS://Dechert.com/"),
                       firm("C2", "Other", "www.other.com")])
        with mock.patch.object(s, "sf_query", org):
            rows = s.pass2_website_match(self.g300, None)
        self.assertEqual([(r["g300_id"], r["candidate_id"]) for r in rows], [("G1", "C1")])

    def test_pass3_catches_variants_short_forms_and_aliases(self):
        org = FakeOrg([
            firm("C1", "DECHERT"),
            firm("C2", "Debevoise and Plimpton"),
            firm("C3", "Uria Menendez"),
            firm("C4", "Dechertson Holdings"),
            firm("C5", "Ogletree"),
            firm("C6", "Ogletree Deakins"),
            firm("C7", "McDermott Will & Emery"),
            firm("C8", "McGuire Woods"),
            firm("C9", "Dechert Kazakhstan Limited"),
            firm("C10", "Davis"),
        ])
        aliases = {"G5": ["McDermott Will & Emery"]}
        with mock.patch.object(s, "sf_query", org):
            rows, skipped = s.pass3_normalized_name_match(self.g300, None, aliases)
        got = {(r["g300_id"], r["candidate_id"], r["signal"]) for r in rows}
        self.assertEqual(got, {
            ("G1", "C1", "name_exact"),
            ("G2", "C2", "name_exact"),
            ("G3", "C3", "name_exact"),
            ("G4", "C5", "name_short_form"),
            ("G4", "C6", "name_short_form"),
            ("G5", "C7", "alias_exact"),
            ("G6", "C8", "name_exact"),
            ("G1", "C9", "name_extends"),
        })
        self.assertEqual(skipped, [])
        # "Davis" starts two different G300 names, so it is attributed to neither.
        self.assertFalse(any(r["candidate_id"] == "C10" for r in rows))

    def test_short_form_not_ambiguous_across_own_aliases(self):
        org = FakeOrg([firm("C1", "Hunton")])
        g = [firm("G1", "Hunton Andrews Kurth LLP")]
        with mock.patch.object(s, "sf_query", org):
            rows, _ = s.pass3_normalized_name_match(g, None, {"G1": ["Hunton & Williams"]})
        self.assertEqual({(r["candidate_id"], r["signal"]) for r in rows},
                         {("C1", "name_short_form"), ("C1", "alias_short_form")})

    def test_load_aliases_ignores_unknown_ids(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d, "aliases.csv")
            with open(p, "w", newline="") as fh:
                w = csv.writer(fh)
                w.writerow(["g300_id", "alias", "note"])
                w.writerow(["G5", "McDermott Will & Emery", "merger"])
                w.writerow(["NOPE", "Whoever", ""])
            with mock.patch("builtins.print"):
                aliases = s.load_aliases(p, self.g300)
        self.assertEqual(dict(aliases), {"G5": ["McDermott Will & Emery"]})
        self.assertEqual(s.load_aliases("", self.g300), {})

    def test_default_alias_file_parses(self):
        with open(s.DEFAULT_ALIASES, newline="", encoding="utf-8") as fh:
            rows = list(csv.DictReader(fh))
        self.assertTrue(rows)
        for r in rows:
            self.assertRegex(r["g300_id"], r"^[0-9A-Za-z]{18}$")
            self.assertTrue(s.name_key(r["alias"]), r["alias"])

    def test_pass4_case_insensitive_and_no_auto_number(self):
        self.assertNotIn("SF_ALM_ID__c", s.IDENTIFIER_FIELDS)
        org = FakeOrg([firm("C1", "Whatever", ALM_Account_ID__c="0013600000rqkukaa5")])
        with mock.patch.object(s, "sf_query", org):
            rows = s.pass4_identifier_match(self.g300, None)
        self.assertEqual([(r["candidate_id"], r["signal"]) for r in rows],
                         [("C1", "identifier_match:ALM_Account_ID__c")])

    def test_pass5_flags_gaps_and_non_firm_g300(self):
        g = [firm("G1", "A", None, No_of_Offices__c=0, Model_Segmentation__c=None),
             firm("G2", "B", "www.b.com")]
        nf = [{"Id": "O1", "Name": "Freeman Mathis & Gary, LLP",
               "RecordType": {"Name": "Office"}, "CreatedDate": "2021"}]
        gaps = s.pass5_completeness_gaps(g, nf, {"G2": 29})
        self.assertEqual([(x["g300_id"], x["issues"]) for x in gaps], [
            ("G1", "blank_website;blank_segmentation;zero_or_null_offices;no_child_office_records"),
            ("G2", "office_count_stale:field=5,actual=29"),
            ("O1", "g300_flag_on_non_firm_record:Office"),
        ])

    def test_pass6_within_g300(self):
        g = self.g300 + [firm("GA", "Dechert", None, ALM_Account_ID__c="0013600000rqkukaa5"),
                         firm("GB", "FBT Gibbons LLP", "www.fbtgibbons.com"),
                         firm("GC", "Frost Brown Todd")]
        rows = s.dedupe_candidates(s.pass6_within_g300(g, {"GB": ["Frost Brown Todd"]}))
        got = {(r["g300_id"], r["candidate_id"], r["signal"]) for r in rows}
        self.assertEqual(got, {
            ("G1", "GA", "within_g300:identifier_match:ALM_Account_ID__c, within_g300:name_exact"),
            ("GB", "GC", "within_g300:alias_exact"),
        })

    def test_dedupe_merges_signals(self):
        g, c = self.g300[0], firm("C1", "Dechert", "dechert.com")
        rows = s.dedupe_candidates([s.candidate_row("website_domain_match", g, c),
                                    s.candidate_row("name_exact", g, c)])
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["signal_count"], 2)
        self.assertEqual(rows[0]["signal"], "name_exact, website_domain_match")
        self.assertEqual(rows[0]["tier"], 1)

    def test_match_tier(self):
        self.assertEqual(s.match_tier({"name_exact"}), 1)
        self.assertEqual(s.match_tier({"within_g300:alias_exact"}), 1)
        self.assertEqual(s.match_tier({"name_short_form", "website_domain_match"}), 2)
        self.assertEqual(s.match_tier({"website_domain_match"}), 3)
        self.assertEqual(s.match_tier({"identifier_match:ALM_Account_ID__c"}), 3)

    def test_triage_evidence_counts_office_hierarchy(self):
        g, c = self.g300[0], firm("C1", "Dechert", CreatedDate="2026-08-20T18:15:47.000+0000")
        rows = s.dedupe_candidates([s.candidate_row("name_exact", g, c)])

        def fake(query, target_org):
            if "FROM Account" in query:
                return [{"k": "G1", "n": 40}, {"k": "C1", "n": 1}]
            if "FROM Contact" in query and "Account.Ultimate_Account__c" in query:
                return [{"k": "G1", "n": 1819}]
            if "FROM Contact" in query:
                return [{"k": "G1", "n": 3}]
            if "FROM Opportunity" in query and "Account.Ultimate_Account__c" in query:
                return [{"k": "G1", "n": 2499}]
            return []

        with mock.patch.object(s, "sf_query", fake):
            s.add_triage_evidence(rows, None)
        r = rows[0]
        self.assertEqual((r["g300_child_offices"], r["candidate_child_offices"]), (40, 1))
        self.assertEqual((r["g300_contacts"], r["g300_opportunities"]), (1822, 2499))
        self.assertEqual((r["candidate_contacts"], r["candidate_opportunities"]), (0, 0))
        self.assertEqual(r["candidate_is_older"], "N")


if __name__ == "__main__":
    unittest.main()
