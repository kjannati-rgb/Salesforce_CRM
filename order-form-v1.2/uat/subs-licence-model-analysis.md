# Subscription deals vs Order Form licence models (PROD, Closed Won lines, last 180 days, as of 2026-08-13)

Read-only analysis of how Lexology Pro, Law.com and GAR subscription deals would map onto the
v1.2/v1.3 licence models (Authorised Users / Limited Access / Benefiting Group / Enterprise-Wide),
and where the user count lives for each family.

## Where the "number of users" actually lives

| Family | Count field in real use | Evidence |
|---|---|---|
| Lexology Pro (legacy products) | `SBQQ__Quantity__c` | "Lexology Pro - In House" (210 lines) + "Law Firm" (44): quantity 1-30, seats always 1 |
| Lexology PRO - IH (current product) | none - group licence | 359 lines: quantity=1, seats=1, `Benefitting_Group_Type__c` = "Corporate" |
| Law.com (all ALM subs) | **`Number_of_Seats__c`** | 2,581 lines: quantity always ~1, seats avg 145-580 per product (this is "the ALM field") |
| GAR | none - tier in product name | Individual/Team/Office/Group/Firmwide License products; quantity ~1 (Team max seen: 5) |

`Number_of_Users__c` (picklist) is NULL on every line in all three families - dead field for subs.
`Employee_Headcount__c` also null throughout.

**Scope correction (Kam 2026-08-13):** the Order Form covers SUBSCRIPTION products only.
Non-subs GAR items in the 180-day data (Awards/Academy delegate tickets, Guides, Know-how
editions, firm profiles) never appear on this Order Form and are out of scope. Lexology PRO
Insights editions likewise if they are not sold as subscriptions.

## Treatment map

| Product (180d CW lines) | Licence model | Count/description source |
|---|---|---|
| Lexology PRO - IH (359) | **Benefiting Group** ("Corporate") | `Benefitting_Group_Type__c`/`Benefitting_Group__c` -> Benefiting_Group_Description; no seat count |
| Lexology Pro - In House (210) / Law Firm (44) | **Authorised Users** | count = `SBQQ__Quantity__c` |
| Lexology PRO Insights - per-jurisdiction (~150 across editions) | inherit parent subscription (content add-on) | n/a - decision needed on whether the licence column prints for add-on lines |
| Lexology PRO - Scanner API (14) | n/a (machine access) | decision needed |
| Law.com / Law.Com International / News Vault / Compass / Radar / Pro (2,581) | **Limited Access** ("Up to N users") | count = `Number_of_Seats__c` |
| GAR - Individual License (74 incl. Standard) | **Authorised Users** | count = 1 (or quantity) |
| GAR - Team License (81) | **Limited Access** | team size is a commercial construct, count not reliably in data (qty mostly 1, max 5) -> product-level default needed |
| GAR - Office License (38) | **CORRECTED (Kam 2026-08-13): not Benefiting Group** - commercially a flat list price x quantity product | licence wording ruling needed: none of the four v1.3 sentences describes it; product name itself carries the scope |
| GAR - Group License (27) | **Benefiting Group** | description needs capturing per deal |
| GAR - Firmwide License (30) | **Enterprise-Wide Access** | warranted headcount not captured anywhere today -> new data point for reps |
| GAR - Bespoke License (6) | per-deal manual | rep sets model + values |
| GAR - Subscription ART (21) | Authorised Users | count = quantity |

## Subs - Specialist Platforms family ruling (Kam 2026-08-14)

The whole family (101 active products: GAR/GBRR/GCR/GDR/GIR/GRR/IAM/LL/WTR x
Individual/Team/Office/Group/Firmwide/Bespoke License + Print Copies + 4 odd subs) is
**always list price x quantity** - except Bespoke License, which is a bespoke price.
Licence scope lives in the product NAME (the tier/licence type); any specifics such as
team size are captured per deal in **Special Instructions or Special Terms** (now
sections 6/7 of the Order Form).

**Treatment: NO `License_Model__c` default on any Specialist Platforms product -> the
licence column prints blank for the whole family.** That is the field's natural unset
state, so zero seeding work is required for these 101 products. The earlier
Individual/Team/Office/Group/Firmwide mapping proposals for GAR are superseded.

Licence-model seeding scope therefore narrows to the Lexology Pro and Law.com families
(per the earlier mapping: Lexology legacy = Authorised Users x quantity; Lexology PRO-IH
= Benefiting Group; Law.com = Limited Access with Number_of_Seats).

Catalog hygiene: "GCR – Standard – Individual License" (01tTm000000ZYN1IAO) uses
en-dashes instead of hyphens - flagged to Kam for a PROD name fix.

## Law.com family ruling (Kam 2026-08-18) - IMPLEMENTED

The licence model is REGION-dependent, not product-dependent: sold out of the USA =
seat-based (Limited Access); sold out of EMEA/APAC(HK) = Benefiting Group. Price is a
price rule in both cases (pricing mechanics, out of scope for the licence column).
Region signal = the opportunity's Billing_Entity__c (ALM/LLC = USA; others = EMEA/APAC).

Implemented as before-save flow `QuoteLine_Stamp_License_Model` (KJDEV + FULLUAT):
for lines in families 'Subs - Law.com' / 'Subs - Law Journal Press' with a blank
License_Model__c -> ALM/LLC-billed = "Limited Access", otherwise "Benefiting Group";
plus a write-when-blank copy of Number_of_Seats__c -> Authorised_User_Count__c on any
Limited Access line. Rep override always wins (blank-only stamping). Verified both
paths in KJDEV (LBR->Benefiting Group; ALM+894 seats->"Up to 894 authorised users").

Benefiting Group description (all families) assembles in the display formula:
explicit description > Function_Name__c (+Group_Size__c "comprising approximately N
individuals") > Benefitting_Group__c picklist (+size) > plain "Benefiting Group" label.

Catalog hygiene for Kam (family-based logic misses these until fixed):
- "Law.com Pro" (01tTm00000BmSIFIA3): Family is BLANK -> set 'Subs - Law.com'
- "Law.com Site License" (01tPx00000DWNR0IAP): Family is 'Law.com' (non-standard) -> set 'Subs - Law.com' if in scope
- "GCR – Standard – Individual License" (01tTm000000ZYN1IAO): en-dash name fix (flagged earlier)

## MBL Seminars family ruling (Kam 2026-08-18) - IMPLEMENTED

Family 'Subs - MBL Seminars', 5 active products. PROD data (180d CW): the seat count lives
in `SBQQ__Quantity__c` (MBL+ Seat Based: 747 lines, qty 1-1,000 avg ~50; Annual Webinar 74;
Seat Based Annual Webinar 14; MBL+ Subscription 199 all-time). `Number_of_Seats__c` is
ALWAYS 1 on MBL lines - dead field for this family.

- **MBL+ Seat Based Subscription / MBL+ Subscription / Annual Webinar Subscription /
  Seat Based Annual Webinar Subscription -> "Limited Access"** (product-level default via
  seed-license-models.js; block pricing is a pricing mechanic, out of scope for the licence
  column - same ruling as Law.com price rules). Count = quantity, copied write-when-blank
  into `Authorised_User_Count__c` by the flow.
- **MBL Credit -> licence column prints BLANK** (custom price added to editable list price;
  no licence dimension - same treatment as Specialist Platforms price-x-qty products).

Flow change (`QuoteLine_Stamp_License_Model`): the count-copy is now FAMILY-AWARE -
Law.com copies `Number_of_Seats__c`, MBL copies `SBQQ__Quantity__c`. Without the family
guard the old rule would have copied the constant seats=1 onto MBL lines (bug caught
before it shipped). Verified in KJDEV: MBL+ qty 50 -> "Up to 50 authorised users";
MBL Credit blank; ALM Law.com regression -> "Up to 250" intact. Seeded KJDEV + FULLUAT
(4 products each; MBL Credit skipped).

## Implementation implications (proposals, not yet built)

1. **Product-level defaults (twin-field pattern):** set `License_Model__c` on each subscription
   product per the map above - one data-load script, values flow to every new quote line, rep can
   override. Offer: script it once the map is signed off.
2. **Count fallback in the display formula:** `Authorised_User_Count__c` blank ->
   fall back to `Number_of_Seats__c` (when > 1, i.e. ALM pattern) -> else `SBQQ__Quantity__c`
   (Lexology legacy pattern). One formula change; keeps reps' explicit value authoritative.
3. **Benefiting-group description:** for GAR Office/Group and Lexology PRO-IH Corporate deals,
   `Benefiting_Group_Description__c` needs populating (could default from
   `Benefitting_Group_Type__c` / office name; wording is customer-facing so needs a rule).
4. **Gaps the new form will surface:** Firmwide/Enterprise deals have no warranted headcount
   today (blank on the form until reps capture it); Insights add-ons and Scanner API need a
   ruling on whether the licence column prints at all for non-seat lines.
