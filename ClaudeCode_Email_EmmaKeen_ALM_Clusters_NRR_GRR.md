# Draft email — Emma Keen (Head of Commercial Finance)

**Subject:** ALM multi-opportunity clusters — what the new analysis shows and what consolidation would mean for NRR/GRR

---

Hi Emma,

Following a request from the CRO I've completed an analysis of historic ALM deals, and I wanted to walk you through it before it reaches you second-hand, because the findings touch retention metrics that Commercial Finance owns.

**What the file is**

`ALM_Multi-Opp_Cluster_Analysis_2026-07-02.xlsx` (I'll share it alongside this email) analyses every Closed Won opportunity migrated from ALM's legacy Salesforce — 69,884 records. It identifies "clusters": groups of two or more opportunities on the same account, same owner, same close date — i.e. deals that commercially were one sale to one client but were recorded as several opportunities. The workbook has five sheets: a summary with methodology, one row per cluster, the underlying opportunity detail with record links, a looser "within 7 days" view, and a league table by owner.

Headline numbers:

- **4,155 clusters** covering **15,619 opportunities** — about 22% of all ALM Closed Won records — worth **£24.77M** (org-converted GBP), spanning 2019–2026.
- If each cluster were a single opportunity, the record count would fall by ~11,500 and the average sold deal size inside these clusters would rise from roughly **£1.6k to £6.0k** (~3.8x).
- Important context: most of this is a **source-system artefact, not rep behaviour** — ALM's old system modelled one product/brand per opportunity, so a three-product sale arrived with us as three opportunities. Individual subscriptions and monthly/quarterly billing also legitimately produce multiple same-day records.
- One data-quality flag for you: **179 records (£2.76M, 2016–2020) have no account** attached and can't be included in any client-level view.

**What this means for NRR / GRR**

The key point first: consolidating clusters doesn't change a pound of actual revenue. What it changes is the measurement grain, and that moves some metrics and not others:

- **Value-based NRR/GRR at account level — largely unaffected.** If your retention calc sums revenue per account cohort, the same pounds are in the base either way.
- **Count-based renewal and churn rates — materially affected.** Today, a client with three fragmented opportunities who renews two of them shows as a churned contract. Consolidated, the same outcome is one renewed opportunity at a lower value — i.e. **contraction, not churn**. Count-based GRR and logo-churn figures would improve on consolidation; that improvement is reclassification, not economic recovery, and we should present it as such.
- **Renewal forecasting and pipeline hygiene — improved.** Fewer, larger renewal events; renewal linkage stops being split across sibling records; expansion sold alongside a renewal is attributable to it rather than floating as a separate record.
- **Average deal size, win-rate denominators, rep productivity metrics — all re-base.** Anything divided by "number of opportunities" shifts when the denominator drops by 11,500.

**Options, effort and risk**

*Option A — reporting-layer fix (recommended).* Keep records as they are; persist the Cluster ID on each opportunity (or in the BI layer) and compute retention metrics at cluster grain. The matching logic is already built and validated. **LOE: ~3–5 days** plus your validation. **Risk: low** — no records change, fully reversible, and Finance can run old and new views side by side before switching anything reported.

*Option B — go-forward guardrails.* A warning at opportunity creation when an open sibling exists on the same account/owner/date, plus quoting discipline so multi-product sales are one opportunity with multiple lines. **LOE: ~1–2 weeks** including testing and sales comms. **Risk: moderate** — needs carve-outs for the legitimate cases (individual subs, differing billing frequencies) or it will generate noise and get ignored.

*Option C — physically merging the historic records.* Restating 15,619 closed opportunities into 4,155. **LOE: 4–8+ weeks** and I'd advise against it: it means reparenting line items, quotes, contracts and contact roles at scale; it breaks the mapping back to ALM's legacy IDs (our audit trail to their system); it risks disturbing renewal chains that hang off those records; and it silently restates every historic number already reported. It's also effectively irreversible.

The honest summary: A gives you nearly all of the analytical benefit at a fraction of the risk; C buys tidiness at the cost of auditability. My recommendation is A now, B next quarter, C not at all.

Happy to take you through the workbook — the Summary sheet states the ground rules verbatim so your team can challenge the methodology directly. If you'd like, we can also re-cut retention on the cluster grain for one brand as a pilot before touching anything reported.

Best regards,
Kamyar Jannati
Head Data and CRM

---

*Attachment to include: ALM_Multi-Opp_Cluster_Analysis_2026-07-02.xlsx*
