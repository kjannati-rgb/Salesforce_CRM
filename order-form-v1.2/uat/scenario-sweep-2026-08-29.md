# Order Form scenario sweep — 29 Aug 2026 (pre-go-live validation)

16 Order Forms rendered from **real production quotes**, one per scenario, selected automatically
(most recent quote whose highest-value line carries the target brand). Each quote was licence-healed
and re-stamped before rendering; all test documents were deleted after download. PDFs:
`scenario-*.pdf` (sent to Kam 29 Aug).

## Brand logo matrix — 13/13 correct

| Scenario | Quote | Logo stamped | Result |
|---|---|---|---|
| GAR lead | Q-222935 | Brand_Logo_GAR | PASS |
| GCR lead | Q-222869 | Brand_Logo_GCR | PASS |
| GIR lead | Q-222910 | Brand_Logo_GIR | PASS |
| GRR lead | Q-222838 | Brand_Logo_GRR | PASS |
| IAM lead | Q-222903 | Brand_Logo_IAM | PASS |
| WTR lead | Q-222833 | Brand_Logo_WTR | PASS |
| LACCA lead | Q-222904 | Brand_Logo_LACCA | PASS |
| Latin Lawyer (LL) lead | Q-222783 | Brand_Logo_Latin_Lawyer | PASS |
| Law.com lead | Q-222930 | Brand_Logo_Law_com | PASS |
| Lexology (Panoramic) lead | Q-222916 | Brand_Logo_Lexology | PASS |
| Lexology Index lead | Q-222906 | Brand_Logo_Lexology_Index | PASS |
| Lexology Pro family override | Q-222908 | Brand_Logo_Lexology_PRO | PASS |
| Unmapped brand (MBL) → fallback | Q-222934 | Centellic_Logo_2026 | PASS |

## Terms / entity / API — all fired

| Scenario | Quote | Observed | Result |
|---|---|---|---|
| Key Account terms (GES&M owner role) | Q-222928 | "General Subscription Terms of Business (Key Account)" | PASS |
| API terms (Scanner API line) | Q-222871 | Includes_API_Access = true; line prints "Includes API access (API Terms apply)"; BG description prints | PASS |
| ALM GLOBAL, LLC entity (US) | Q-222930/Q-222928 | "ALM GLOBAL, LLC" + New York law | PASS |
| LBR entity | multiple | "Law Business Research Limited (Trading as "Centellic")" | PASS |
| MBL entity | Q-222934 | "MBL Seminars Limited (Trading as "Centellic")" | PASS |
| GHK billing entity | Q-222935 | Initially "Law Business Research Limited" — config defect, FIXED same day (see finding 2) | FIXED |

## Licence wording observed across the set

Group License, Individual License, Team License (product defaults) · Limited Access – Up to N
(incl. 894-seat Law.com Radar and 5-seat MBL+) · Authorised Users – 1 named authorised user
(singular grammar) · Benefiting Group with rep description. Firmwide price-flag and "Included"
add-on were exhaustively validated 28 Aug on Q-187142 (not re-run). **Enterprise-Wide Access: no
real quote encountered — untested against live data.**

## Findings for review (none block go-live)

1. **Products with no licence model default print a blank Licence Model cell.** Seen on: GCR 100 /
   GRR 100 Firm Profiles, Lexology Panoramic edition products, Lexology Index country reports,
   Daily Business Review Online, and event-sponsorship items. Products data gap, not a template
   defect — same class as the GAR ART case (fixed via the "Included" model). Recommend: product
   owners assign License_Model__c defaults (or "Included") to these families as encountered.
2. **GHK entity block printed "Law Business Research Limited"** — config defect in the GHK CMDT
   row: the matcher field (Entity_Value__c) correctly said the Asia entity but the display field
   (Legal_Entity_Name__c) held the UK name. **FIXED 29 Aug on Kam's ruling** to "Law Business
   Research (Asia) Limited"; deployed to KJDEV/FULLUAT/PROD and re-verified live on Q-222935.
   Registration number, registered office (Hong Kong) and English governing law were already
   correct and unchanged.
3. Several brand-lead quotes found were **events sponsorship deals** (IAM/LACCA/LL) — they rendered
   fine for logo validation, but events deals will use their own template when that lane is built;
   their blank licence cells are expected.

Sweep driver: scratchpad `scenario-sweep.py` (re-runnable; select/heal/stamp/render/verify/clean
per scenario).
