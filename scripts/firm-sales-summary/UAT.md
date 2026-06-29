# Firm Sales Summary — UAT script (KJDEV)

Feature: persisted USD rollups on the Firm account + a reportable group child object + the
`firmSalesSummary` LWC. Built on branch `feature/firm-sales-summary`. **KJDEV only — not deployed to production.**

## 0. One-time setup (admin)
1. **Assign the permission set** `Firm Sales Summary` to each UAT user (grants FLS on the new
   Account fields + the child object + the controller):
   `sf org assign permset --name Firm_Sales_Summary --target-org KJDEV`
2. **Place the component:** open the **Firm** Lightning record page in the Lightning App Builder,
   drag **Firm Sales Summary** onto the page, Save & Activate. (The raw fields are also on the
   `Account-Firm Layout` under the **Firm Sales Summary (USD)** section.)
3. **Backfill** the rollups once (already run during build):
   `Database.executeBatch(new FirmRollupBatch(), 10);`
4. **Schedule** the nightly reconcile (~02:00 Europe/London):
   `System.schedule('FSS nightly rollup', '0 0 2 * * ?', new FirmRollupBatch());`

## 1. Headline (persisted, instant)
- Open a Firm account with closed-won opportunities under its offices.
- Confirm the **Net Won Value (USD)**, **Won Opportunities**, **Cancellations** (count + value) and
  **Active Subscriptions** cards render, all money formatted **$** regardless of your user currency.
- Toggle **Period** (All-time / This FY / Last FY / Last 12 mo) → KPIs + YoY bar update instantly.
- Verify **all-time net = This FY + Last FY + earlier years** and that cancellations are netted in.

## 2. Commercial-group breakdown (persisted)
- The **By commercial group** panel lists groups with **Value (USD)** + **Items**.
- Confirm **Events** is split into **Events - Sponsorship**, **Events - Delegate Ticket** and
  **Events - Other** (the latter absorbs blank / Webinar product types).
- Σ of group values should track the firm Net Won Value (within FX grain; exact opp-set parity is
  the reconciliation script's job).

## 3. Office breakdown + drill-down (live)
- The **By office** panel shows value / won / subs per office.
- Click a group row or an office row → the **Opportunities** drill opens, paginated (10/page).
- Use **Prev/Next**; confirm the count ("1–10 of N") and that **Amount (USD)** is shown per row,
  cancellations flagged in red.
- Switch the **Business** toggle (All / New / Renewal) → the office panel + drill filter by
  Opportunity Type (headline/groups remain all-business by design — persisted).

## 4. Refresh
- Click **Refresh now** → toast "Recompute queued"; the **Last refreshed** stamp updates a few
  seconds later (async recompute for this firm).

## 5. Near-real-time triggers
- Edit an opportunity under the firm (change Amount / Stage to Closed Won / re-parent
  `Ultimate_Account__c`) → within a moment the firm headline reflects the change (Opportunity
  trigger → queueable). Re-parenting recomputes BOTH the old and new firm.
- Add / expire / terminate a subscription → **Active Subscriptions** updates.

## 6. Reporting
- New report type **"Accounts with Firm Product Group Rollups (USD)"** → build a report of firms
  with their commercial-group USD rollups.

## 7. Reconciliation (pre-decommission, run in PRODUCTION)
- `sf apex run --file scripts/firm-sales-summary/reconcile.apex` — asserts exact COUNT parity vs
  the legacy rh2 opp set and explains the USD-vs-rh2 value delta.
- `./scripts/firm-sales-summary/reference_scan.sh` — **must show zero CONSUMERS** before rh2 is
  decommissioned. (Current scan finds live consumers — see the build report.)

## Known notes
- KJDEV holds almost no sales data, so most firms show 0; correctness is proven by the Apex suite.
- A few `ZZDIAG_*` records exist in KJDEV from a build-time diagnostic (Closed-Won opps are
  delete-protected); harmless, safe to leave or clean via the data team.
