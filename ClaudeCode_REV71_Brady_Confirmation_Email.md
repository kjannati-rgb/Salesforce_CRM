# Draft email to Brady — REV-71 final confirmation (one question)

**To:** Brady Blevins (bblevins@alm.com)
**Cc:** Cayla / Amy Hahn (ahahn@alm.com)
**Subject:** REV-71 invoice codes — one confirmation before we automate (the 1 vs 3 rule)

---

Hi Brady,

Thank you — your 1 Aug breakdown of the bundle rules was exactly what we needed, and it lines up
with what we'd built. We've confirmed the three Total Contract Value codes against your definitions:

- **Code 1 = Law.com Premium** (primary = enterprise LAWM)
- **Code 2 = Global Leaders in Law** (primary = GLBM)
- **Code 3 = Law.com International** (primary = enterprise LWKM)

…and that Law.com Pro / Mid Market Pro use the Dispatch Code / Promo-'Z' mechanisms, not a TCV code.
All of that is reflected in the automation.

**One thing I need you to confirm, because it decides how the automation behaves on mixed deals.**

Your rules say a **Premium bundle (code 1) cannot contain Law.com International (LWKM)** — LWKM only
appears under International (code 3) or GLL (code 2). So our automation uses this clean rule:

> If GLL (GLBM) is present → **2**. Otherwise, if Law.com International (LWKM) is present → **3**.
> Otherwise, if Law.com (LAWM) is present → **1**.

In other words: **any deal containing Law.com International, that isn't a GLL bundle, is coded 3.**

The catch: in the historical data, **68 deals contain Law.com International (LWKM) but are coded 1**
(not 3). So either:

1. those 68 were **mis-coded** and should be **3** — in which case our automation is right and we'll
   correct them as part of the clean-up; **or**
2. they're **legitimately 1** (Law.com was the primary product and International was a secondary line) —
   in which case "which product is primary" genuinely matters and we'll need the rep to flag the
   primary product on the bundle.

**Could you confirm:** for a deal that contains Law.com International but is *not* a GLL bundle — is it
**always coded 3**? And specifically, are those 68 historical "code 1 with International present" deals
mis-codings, or correct?

Your answer is the last thing standing between us and turning this on. Happy to walk through examples
on a quick call if easier.

Thanks again,
Kam

---

## Internal notes (not part of the email)
- The engine is **already built both ways' decision point**: the clean-hierarchy version (GLBM>LWKM>LAWM)
  is deployed & tested in KJDEV (REV71_ALMCodeFlow_Test 11/11 green). If Brady says "always 3", we ship as-is.
- If Brady says "depends on primary", we add one rep-set field (Primary Bundle Product / Bundle Type) and
  read that instead — a contained change.
- Evidence for the 68 deals: read-only prod query — `Full_Contract_Value__c = 1` OLIs whose opp also has an
  LWKM line. Attach the list if Brady wants specifics.
- This also lets us rewrite the REV-71 ticket title (currently "auto-assign sequence numbers 1,2,3" — the
  misleading framing; they're bundle-family codes).
