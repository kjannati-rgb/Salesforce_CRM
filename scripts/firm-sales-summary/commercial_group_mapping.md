# Commercial-Group Mapping (`Product_Family_Group__mdt`)

Source of truth = the 37 `Product_Family_Group__mdt` records. `resolveGroup(Family, Product Type 1)`:
exact `(Family, PT1)` → `(Family, blank)` family-default → `Other / POS / Reports`.

**Deviation from brief §6:** `Subs - Docket Navigator` is its **own group `Docket Navigator`** (was
folded into `Law.com / ALM`). Changed 2026-06-29 at the user's request; 972 FULLUAT firms recomputed.

| Commercial Group | Product2.Family (Product Type 1) |
|---|---|
| Lexology PRO & Intelligence | Subs - Lexology Pro |
| Lexology Intelligence | Subs - Lexology Intelligence |
| Lexology Insight | Subs - Lexology Insight |
| Lexology Compete | Subs - Lexology Compete |
| Lexology Academic | Subs - Lexology Academic |
| Lexology Index | Performance Data - Lexology Index |
| Lexology In-Depth | Expert Insight - Lexology In-Depth |
| Lexology Panoramic | Expert Insight - Lexology Panoramic |
| Expert Insight (GxR / IP) | Expert Insight - GXRs · Expert Insight - IP |
| Performance Data - GxR/IP | Performance Data - GxR/IP |
| Law.com / ALM | Subs - Law.com · Subs - Law Journal Newsletters · Subs - Law Journal Press · POS - Law Journal Press · Subs - VerdictSearch · POS - VerdictSearch · Subs - CLE · Subs - Digital Rights · Subs - Reports · Subs - Regional · Subs - Memberships · Subs - China Law & Practice |
| **Docket Navigator** | **Subs - Docket Navigator** *(was Law.com / ALM)* |
| AllHires / Law Careers Net | Law Careers Net · AllHires |
| MBL Seminars | Subs - MBL Seminars |
| Specialist Platforms | Subs - Specialist Platforms |
| Advertising | Advertising |
| Legal Monitor | Subs - Legal Monitor |
| Other / POS / Reports | Instruct Counsel · Book Sales · Consulting · POS - Reports |
| **Events - Sponsorship** | Events · PT1 = `Sponsorship` |
| **Events - Delegate Ticket** | Events · PT1 = `Ticket` |
| **Events - Other** | Events · PT1 = blank / `Webinar` / other |

To change a mapping: edit the matching `customMetadata/Product_Family_Group.<DevName>.md-meta.xml`
`Commercial_Group__c`, deploy the CMDT record, then recompute affected firms (firms with that
family's won-lines) via `FirmRollupQueueable` — config-only, no Apex change.
