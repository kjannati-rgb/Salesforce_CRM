# G300 duplicate sweep - 26 Sep 2026

Read-only sweep of the 302 Account records with `G300_Account__c = true`
(Firm record type) in Production, looking for other Firm records that are
the same firm. Nothing was changed in Salesforce. **No record is to be
merged, re-parented or edited without sign-off from Kamyar Jannati.**

## Files

| File | What it is |
|---|---|
| `g300_duplicate_candidates.csv` | Raw output of `scripts/g300-dedup/g300_dedup_sweep.py`: 376 candidate pairs with signals, tier and triage evidence |
| `g300_candidates_verified.csv` | The same 376 pairs with a verdict per row (`final_classification`), both reviewers' calls and their evidence |
| `g300_missed_by_sweep.csv` | 38 further records found by a separate search and confirmed, which the sweep did not flag |
| `g300_completeness_gaps.csv` | Data problems on the G300 records themselves |
| `g300_sweep_summary.txt` | The script's run summary |

Email addresses in the evidence text are cut to their domain.

## Results

| Verdict | Pairs | What to do |
|---|---|---|
| duplicate | 185 (100 G300 firms) | Merge into the G300 record after checking the evidence |
| predecessor_or_legacy | 55 | Former or merged-in firm names: merge the live ones, keep deliberate history |
| affiliate_or_office | 20 | Country entities and offices recorded as a Firm: re-parent as an Office |
| person_or_misfiled | 35 | People, placeholders and non-law organisations carrying a firm's website: clean up |
| disputed | 5 | Reviewers disagreed; needs a decision |
| unrelated | 75 | Different organisations; no action |
| within the G300 set | 1 | "Frost Brown Todd" (001Px00000j5PGuIAM) is G300-flagged but is the pre-merger name of G300 "FBT Gibbons LLP", created 20 Aug 2026 |

The 185 duplicates hold 202 child Offices, 279 contacts and 2,356
opportunities (counted across each record's Office hierarchy), so a merge
has to decide where those go; they are not empty shells.

Where they came from: 161 of the 185 were created by three bulk loads
under Kieran Hansen's user:

| Load | Firm records it created | Confirmed G300 duplicates among them |
|---|---|---|
| 25 Jul 2026 | 9,345 | 64 |
| 20 Aug 2026 | 4,801 | 86 |
| 22 Aug 2026 | 246 | 11 |

The duplicate rate across those ~14,400 records is unknown beyond the G300
firms, and the source of the loads needs fixing or merged records will come
back. (13 Nov 2025, 99,655 Firm records, was the org migration, not a
duplicate load.)

G300 record issues: 152 of the 302 have `No_of_Offices__c` disagreeing
with their number of child Office records (Dechert: 1 vs 29); 4 Office
records carry the G300 flag (Freeman Mathis & Gary); 3 G300 records have
no segmentation and Frost Brown Todd has no website.

## How it was produced

1. The script was reviewed against live data; defects that hid real
   duplicates (case-sensitive matching, punctuation and "&"/"and"
   variants, short names, renamed firms, a silent 5-character cut-off)
   were fixed. See the commit history of `scripts/g300-dedup/`.
2. The script ran unmodified with its queries answered through a
   read-only Production connector (the `sf` CLI was not available); the
   results come from the raw query responses.
3. Every candidate pair was re-checked against the live records by an AI
   reviewer (Claude) and challenged by a second, independent one. They
   agreed on 371 of 376; the other 5 are `disputed`. A live re-query of
   every candidate matched the sweep's names, record types and flags
   (376/376).
4. A separate search of all 302 firms (SOSL and alternative name forms)
   proposed 170 possible misses; a second reviewer confirmed 38.

Some verdicts rely on general knowledge of law-firm mergers or on public
web sources, as their evidence text says. Check those before acting.

## Known limits of the sweep

The recall check shows what the name matching still cannot catch:
typos ("Baker Bots", "Lowestein Sandler"), acronyms ("Mwe", "Wsgr",
"Blg LLP"), names that drop the leading partner ("Strauss Hauer Feld"),
city prefixes ("DHH Law Firm") and former names not yet in
`scripts/g300-dedup/g300_aliases.csv`. Fuzzy matching would need a
different candidate query; until then, add known former names to the
alias file.
