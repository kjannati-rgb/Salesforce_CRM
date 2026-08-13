# Order Form v1.2 - Phase 5 UAT results (KJDEV leg, 2026-08-13)

Executed by Claude Code against KJDEV. Cells requiring a linked Adobe Sign account are
deferred to the FULLUAT leg per Kam (2026-08-13). Evidence PDFs in `../reference/`.

| # | Cell | Result | Evidence / notes |
|---|---|---|---|
| 1 | Licence model: Authorised Users | PASS | Q-211543 line renders "...Number of authorised users: 12" |
| 2 | Licence model: Limited Access | PASS | "Up to 25 authorised users (as defined in the General Terms)." |
| 3 | Licence model: Benefiting Group | PASS | "...the following group: the global IP practice group" |
| 4 | Licence model: Enterprise-Wide | PASS | Full warranted-headcount wording incl. "increases by more than 5%." renders (3000 and 1200 variants) |
| 5 | Legal entity: UK entity | PASS | Company block stamps "Law Business Research (UK) Ltd." from CMDT |
| 6 | Legal entity: second entity flip | PASS (structural) | Rep entity flipped to "ALM Global, LLC" -> restamp swapped the whole company block; flipped back cleanly. Reg/office/governing-law text still PLACEHOLDER pending decision 3, so wording itself unverifiable yet |
| 7 | Lines: single line | PASS | Phase 2 draft4 PDF (Q-211545, 1 line) |
| 8 | Lines: 6+ lines / pagination / tag drift | PASS | 8-line PDF: table splits page 1->2 with header re-render, totals + tax + sections 4-8 after, execution tags intact on final page, no drift/clipping |
| 9 | Send path: one-click | PARTIAL | Underlying invocable exercised via REST (success + all failures). The screen-flow UI walk needs a human click-through - and the quick action is not yet on a layout |
| 10 | Send path: zero-click | PASS (to the Adobe boundary) | Draft->Approved with Auto_Send + signatory + doc fired the flow; agreement "Order Form - VALIDATEBATCH2 Account - Q-211545" created (name pattern merges resolved). Recipient/attachment/Quote__c population + dispatch are in the package's send processing, gated on the Adobe account link -> FULLUAT |
| 11 | Send path: precondition messages | PASS | Draft: "The quote must be Approved before sending (current status: Draft)." / no signatory: "No Signatory Contact is set on the quote." / no doc: "No generated quote document exists. Generate the Order Form PDF first." |
| 12 | Write-back: VAT, PO, signed date, PDF | DEFERRED (FULLUAT) | Requires a signed round trip |
| 13 | Regression: existing default template | N/A in KJDEV (PASS by construction) | KJDEV has no other quote templates; ours is SBQQ__Default__c=false. Re-check in FULLUAT/PROD where the real default exists |
| 14 | Regression: renewal automation | PARTIAL | New fields inert; stamping flow ran on every quote save across Phases 2-5 without a single save failure. Dedicated renewal-cycle check belongs to the FULLUAT leg |
| 15 | AA sets Approved (Phase 4 carry-over) | PASS (evidence) | PROD: 2,628 quotes reached Approved in last 30 days; full traced approval deferred to FULLUAT |

## Known flake
CPQ document generation can fail once with "Attempt to de-reference a null object" if invoked
immediately after quote-line DML (recalc contention). Retry succeeds. Consider a retry in any
future automation that generates documents programmatically.

## Outstanding before sign-off
- Human sign-off: Kam + one rep + one Finance reviewer on the PDF output (runbook Phase 5 gate).
- Quick action layout placement (UAT-time step).
- FULLUAT leg: Adobe account link -> round trip (tag placement -> flip tags to white 5px in
  01/04/08 + re-push), write-back cells, one-click UI walk, renewal regression, default-template
  regression, real CMDT values after decision 3.
