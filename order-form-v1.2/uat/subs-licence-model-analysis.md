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
