# REV-60 — Promo/Dispatch validation timing: decision needed before go-live

**Author:** Kamyar Jannati · **Date:** 26 June 2026 · **For:** Cayla / Team Brady (ALM Sales Ops)
**Status:** Phase A engine built & green in KJDEV. This is a **gate before production rollout**, surfaced during the build.

---

## TL;DR

Production already **forces** reps to enter Promo and Dispatch codes by hand, via active CPQ **Validation Product Rules** that fire **inside the Quote Line Editor at Calculate/Save** — *before* any record-triggered automation runs. REV-60's engine writes **after** the save. So as-built, REV-60 cannot satisfy these rules and the rep is still blocked in the editor.

**We need one decision before go-live: how do the codes get written in time?** Either (A) write them during **Calculate** (a CPQ Price Rule / calculator plugin), or (B) **retire/scope** the manual-entry rules for ALM-automated lines and let the engine fill them. Recommendation below is a hybrid.

This does **not** block the Phase A scaffold (built, inert, tested). It blocks **activation in production**.

---

## The rules (production, active)

| Rule | Scope (all conditions) | Evaluates | Effect |
|---|---|---|---|
| **Promo Code Required - Non bundle products** | Quote Line `Division__c = ALM` **and** non-bundle **and** `ProductFamily ≠ Subs - Memberships` **and** Quote not Amendment **and** `Promo_Code__c` blank | **Save** | Blocks save: "You must provide a Promo code for all invoiced items" |
| **Law.com Benefitting Group – Restrict Sales Rep EMEA** | `ProductName = Law.com` **and** Quote `SBQQ__SalesRep__c` ∈ {specific EMEA rep IDs} **and** `Dispatch_Method_Code__c` blank | **Always** | "Please add Dispatch Code as **BE**" |
| **Law.com Benefitting Group – Restrict Sales Rep APAC** | `ProductName = Law.com` **and** Quote `SBQQ__SalesRep__c` ∈ {specific APAC rep IDs} **and** `Dispatch_Method_Code__c` blank | **Always** | "Please add Dispatch Code as **BA**" |

(Plus `LBR - Finance Code Required` / `…Commissioned Content Slot` — finance-code, REV-71-adjacent, out of scope here.)

> **Note:** these rules exist in **production only** — they are **absent in KJDEV** (sandbox drift). So the collision cannot be reproduced in KJDEV; it must be validated in **FULLUAT** (prod-like) before go-live.

---

## Why it collides (the timing)

CPQ Validation Product Rules evaluate in the **Quote Line Editor**, during **Calculate/Save**, *before* the records are committed to the database. REV-60 Layer 1 is an **after-save** record-triggered flow (running in the DB save transaction, after commit). Sequence:

```
Rep clicks Save in QLE
   → CPQ Calculate  → [Promo rule = Save, Dispatch rules = Always] EVALUATE  ← rep blocked here, field still blank
   → (only if they pass) records committed to DB
        → REV-60 after-save engine runs  ← too late: the rep never got past the validation
```

So the engine, as a post-save actor, **cannot** clear these rules. This is structural, not a tuning issue.

---

## What the rules tell us about the determinant (partial §7.1 / §7.2)

- **ALM scope is `Quote Line.Division__c = 'ALM'`** (+ non-bundle, non-membership). This is the org's existing ALM marker — cleaner than a ProductCode list, and REV-60's scope should align to it.
- **The Promo rule enforces *presence*, not value** — it does not reveal what the base promo *should be*. **§7.1 (what selects the base) is still the open blocker.**
- **The BE/BA dispatch is driven by the quote's `SBQQ__SalesRep__c`** (hardcoded rep user IDs) for Law.com — i.e. **rep/region-specific**, and brittle (breaks when reps change). It is *not* a clean "Benefitting Group" field on the line.

---

## Options

**A — Write at Calculate (CPQ Price Rule or Quote Calculator Plugin).**
Codes appear before the validation fires. *Pros:* satisfies the rules natively; no rep friction. *Cons:* the base+suffix+Z composition is hard to express declaratively in a Price Rule; a QCP is a single org-wide plugin (heavier governance); duplicates the tested Apex engine logic.

**B — Retire/scope the manual-entry rules; let the after-save engine fill.**
*Pros:* simplest; the Promo rule's entire purpose — *force manual entry* — is obsoleted once REV-60 reliably fills the field. *Cons:* a brief blank window between save and the engine; needs confidence the engine always fills in-scope lines; the **Always**-evaluated dispatch rules are harder to scope than the **Save** promo rule.

**C — Hybrid (recommended).**
- **Promo:** scope the "Promo Code Required" rule to **exclude lines REV-60 auto-fills** (or downgrade to a warning). The rule only checks presence, and the engine *guarantees* presence for in-scope ALM lines — so the manual gate becomes redundant.
- **Dispatch:** fold the **rep/region → BE/BA** logic into REV-60 config (CMDT + the engine, or a small Price Rule) and **retire the hardcoded-user rules**. This both fixes the timing and removes the brittle user-ID dependency.

---

## Asks (Cayla / Team Brady)

1. **Confirm §7.1** — the base-promo determinant and the quote-line field that carries it (the blocker; the validation doesn't answer this).
2. **Choose the write-timing approach** (A / B / C) per field — this decides whether REV-60's writer stays after-save or moves to Calculate.
3. **Confirm** whether the BE/BA rep/region dispatch logic should move into REV-60 config (recommended — retires the brittle user-ID rules).
4. **Acknowledge** the FULLUAT requirement: KJDEV lacks these rules, so validation behaviour must be proven in a prod-like sandbox before go-live.

---

*Engine status: Phase A scaffold deployed to KJDEV, inert (all kill switches OFF), 15/15 regression tests green (engine 91%, wrapper 100% coverage). No production change has been made.*
