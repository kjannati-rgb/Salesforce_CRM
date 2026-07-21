# REV-60 — Post-go-live hardening, Mon 20 Jul 2026

Both items deferred from the Friday-night cutover are **done and live in PROD**. This note covers
what changed, the one thing still needing a human, and the two follow-ups.

---

## 1. Dispatch backstop re-armed (LAWM / LWKM / NYOM) — with line-level grandfathering

**What changed.** The backstop now only enforces a required-but-blank `Dispatch_Method_Code__c` on
lines created **on/after a configured cutoff**. Legacy lines are never hard-blocked.

| Setting | Value |
|---|---|
| `Enforce_Dispatch_After__c` (new) | `2026-07-20T15:35:00Z` — the re-arm instant |
| `Dispatch_Required_Product_Codes__c` | `LAWM;LWKM;GLBM;GLBM - Team Membership;GLBM - Individual Membership;NYLM;NYOM` |

Deploys: KJDEV 37/37 → PROD `0AfPx000001HY6LKAW` (37/37) → atomic Control `0AfPx000001HY9ZKAW` (37/37).

**Why the cutoff is the re-arm instant, not go-live.** Everything quoted during the softened weekend
(264 quote lines) is grandfathered along with the ~914 legacy open quotes. Reps saved those blank
*because* the system had stopped asking; blocking them retroactively would have been the wrong surprise.

**Proof (PROD, savepoint/rollback, zero footprint).** On `Q-217988` — the same quote flagged during
Friday's incident:

- Its three legacy blank-dispatch lines (LAWM, LNVM, LWKM, created 17 Jul 15:09) → `hasGap=false`, **no block**.
- A brand-new LAWM line added to that *same* quote → **blocked**:
  `1 ALM line(s) still need a required code: LAWM (dispatch). Enter the Dispatch code for the access level: ON (1 user), OS (site licence), OE (enterprise), OL (Pro/firmwide).`

The **"1"** is the whole proof: three grandfathered lines sat on that quote and none of them counted.

**Rollback (instant):** redeploy Control with `LAWM;LWKM;NYOM` removed, or blank the cutoff to revert
to enforce-always.

---

## 2. Promo rule re-scoped and reactivated

`Promo Code Required - Non bundle products` (`a18Px00000ORHwbIAH`) is **active again**, but now fires
only on Division=ALM products **outside** the 24-code engine scope.

Mechanism: new QuoteLine formula checkbox `Engine_Scoped_Promo__c` (true for the 24 engine codes),
plus a 6th error condition `Engine_Scoped_Promo__c equals False`. `ConditionsMet = All`, so an
engine-managed code can never trip it.

**Verified on 5,848 real ALM lines across 46 product codes — 100% correct.**

| | Products |
|---|---|
| **Blocks** (promo genuinely required) | TXOM, DRGM, PACM, CCAM, DBRM, DDEM, NLOM, CTOM, LARM, BAOM, MLOM … |
| **Never blocks** (engine fills these) | LAWM, LWKM, LGCM, LGLM, LNVM, LRCM, PCEM, NYLM, NYOM, GLBM family, Law.com Pro … |

**Rollback (instant):**
`sf data update record -o PROD -s SBQQ__ProductRule__c -i a18Px00000ORHwbIAH -v "SBQQ__Active__c=false"`

> ⚠️ **Maintenance coupling.** `Engine_Scoped_Promo__c` is a hand-maintained *mirror* of
> `ALM_Code_Engine_Settings__mdt.Control.ALM_Product_Codes__c`, because a formula cannot read Custom
> Metadata. **If you add a product to the engine, add it to the formula in the same change** —
> otherwise the rule will start blocking saves on a code the engine fills.

---

## 3. Needs a human — 3 quotes require a promo code

Reactivation has no grandfathering mechanism, so these existing open quotes will prompt on next save.
This is the complete blast radius (7 lines / 3 quotes). Values were **not** guessed, because these
codes feed Integra:

| Quote | Lines | Created |
|---|---|---|
| Q-210602 | 3 × PACM | 2026-05-15 |
| Q-210607 | 3 × DRGM | 2026-05-15 |
| Q-218101 | 1 × TXOM — Rodriguez Trial Law, rep Mark Tagle | 2026-07-20 |

TXOM history is non-deterministic (`A611` / `A621` / `A641` / `A661` / `!SREN`), so the rep or Willie
should set them.

---

## 4. QLE click-test (5 min — please run to close out)

CPQ product rules fire in the Quote Line Editor calculator, **not** on plain DML, so anon Apex cannot
exercise them. Everything above is verified by construction against live field values; this confirms
it through the UI.

1. Open any open ALM quote → **Edit Lines**.
2. Add a **TXOM** (Texas Lawyer Online) line, leave **Promo Code** blank → **Save**.
   → *expect:* blocked, "You must provide a Promo code for all invoiced items".
3. Fill the promo → Save. → *expect:* saves.
4. Add a **LAWM** line, leave Promo Code blank, put any dispatch (e.g. `OE`) → **Save**.
   → *expect:* **saves**, and the engine stamps the promo (e.g. `!SJSI…`) after save.
5. Add an **NYLM** line, leave Promo blank → **Save**.
   → *expect:* **saves** (dispatch auto-fills `PO`; blank promo is legitimate).
6. On an **existing pre-20-Jul** quote with a blank-dispatch LAWM line, just re-save.
   → *expect:* **no block** (grandfathered).
7. On that same quote, add a **new** LAWM line with blank dispatch → **Save**.
   → *expect:* blocked, "1 ALM line(s) still need a required code".

If step 4 or 6 blocks, roll back with the one-liner in §2 and ping me.

---

## 5. Draft note to Willie — ranked-firm `!SGRP` normalisation (monitor only)

> Hi Willie,
>
> One behaviour I want to confirm before we leave it running.
>
> For ranked firms (AmLaw / NLJ / Global) the engine derives the promo base from the firm's
> segmentation. Where a rep has hand-typed `!SGRP` on a **ranked** firm's Law.com line, the engine
> treats that as its own code and will normalise it to the ranked segment base (`!AMLW` / `!NLJO` /
> `!GLBL`) the next time the quote is saved. That affects roughly **195 existing LAWM lines**.
>
> My read of your rule — *segment wins for ranked* — says this is intended, i.e. `!SGRP` belongs to
> non-AmLaw group/packaged deals and a ranked firm should carry its segment code regardless of what
> was typed. Can you confirm?
>
> If that's right, no change needed and the codes will tidy themselves up as quotes are touched. If
> some ranked firms should legitimately keep `!SGRP`, tell me the signal that distinguishes them and
> I'll add it as a config row — no code change required.
>
> Thanks,
> Kamyar

**No code change made.** Current behaviour = segment wins for ranked firms.

---

## Gotchas worth remembering

- **Take "now" from the org, not the machine.** The container clock initially reported 17 Jul while
  PROD was on 20 Jul. That would have set the cutoff three days stale and hard-blocked 3 real quotes.
  Use the latest `CreatedDate` or `System.now()`.
- **Deploying a custom field via MDAPI grants no FLS to anyone.** `Engine_Scoped_Promo__c` deployed
  "Succeeded" but was invisible even to System Administrator (`No such column`) until FieldPermissions
  were mirrored from `Promo_Code__c` (12 grantees). Formula fields are read-only → `PermissionsEdit=false`.
- **Order matters on the Control record.** Re-adding LAWM/LWKM/NYOM while the cutoff is still null makes
  the engine enforce on *every* line. The codes and the cutoff must land in one deploy.
- **Never push the repo Control file to PROD.** It carries `Master_Active=false` as a safe default and
  would switch the engine off. Retrieve the org's live copy, edit the target fields, deploy that back.
- **REV-60 source is untracked in git** and lives only in `C:\sf-work\kjdev\force-app\...`.
