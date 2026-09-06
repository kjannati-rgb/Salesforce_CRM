# Licence model playbook (rep/UAT reference, 2026-08-20)

Shareable page: https://claude.ai/code/artifact/80330212-c87a-485c-a9f3-b918678d0185
The model is NEVER manual: recomputed from the rules on every line save (self-healing). Reps supply only BG description + US Law.com seats.

## Per family

| Family | Automatic | Rep must | Notes |
|---|---|---|---|
| Specialist Platforms (GAR/GBRR/GCR/GDR/GIR/GRR/IAM/LL/WTR) | Licence-type LABEL from the product (Individual/Team/Office/Group/Firmwide/Bespoke License) | nothing | specifics go in Special Instructions/Terms; Print Copies + one-offs print blank |
| Lexology Pro | current person products -> Benefiting Group; LEGACY In House / Law Firm -> Authorised Users, count = quantity | on every BG line: Benefiting Group Description (preferred) OR Function Name + Group Size | APIs print blank |
| Law.com + Law Journal Press | model follows opp Billing Entity: ALM/LLC -> Limited Access + count from Number of Seats; others -> Benefiting Group | US-billed: ensure Number of Seats; EMEA/APAC: describe the group | region rule, before-save flow |
| MBL Seminars | seat-based products -> Limited Access, count = quantity | nothing | MBL Credit prints blank (a purchase amount, not a licence) |

## Wrong/missing value? Self-healing

1. Save the line (any edit) - model + count recompute from the rules on every save. Open-deal lines bulk-recomputed 2026-08-20 (25 FULLUAT stragglers blocked by their own multi-year-segment VR).
2. Benefiting Group: fill the description (or Function Name + Group Size). US Law.com: ensure Number of Seats.
3. REGENERATE the document (frozen snapshot), then send.

Send gate: sending refuses any Benefiting Group line without a group definition -
one-click names the line; zero-click silently skips. Remedy = step 3, regenerate, resend.

## Count sources

Authorised Users = quantity | Limited Access = seats (US Law.com) or quantity (MBL) |
Benefiting Group = no count, description defines the group | Enterprise-Wide = Warranted Headcount (rep) |
Labels = no count.

