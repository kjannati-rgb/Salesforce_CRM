# REV-71 — Rule clarification needed: do "Law.com Pro" deals get a TCV code?

**For:** Brady (coding-rule owner) · cc Cayla
**From:** Kam (Head Data & CRM)
**Date:** 30 Jun 2026
**Status:** Decision needed — blocks correct handling of comprehensive Law.com deals

---

## The question (one line)
**Should a "Law.com Pro" deal carry an ALM Total Contract Value code (1 / 2 / 3), or be left blank (exempt)?**

We have two stakeholders pointing in opposite directions and I need your ruling to settle it.

## Why it's come up
- **Willie Guerrero (ALM)** flagged the **Skadden Arps** renewal (Q-197826, ~$2.3M) saying *"this should not have a TCV entered as this is a law.com pro opp."*
- But in **UAT, Cayla tested "Law.com Pro → code 1" and passed it.**

So the spec/UAT says **code it**, and the field says **don't**. Both can't be right.

## The technical constraint you need to know
The automation decides the code purely from the **product codes** on the deal (LAWM → 1, GLBM → 2, LWKM → 3, highest-revenue anchor wins). A "Law.com Pro" package is usually sold as **individual product lines** (Law.com, Radar, Compass, International, etc.) — which look **identical** to a normal multi-product Law.com deal.

**Therefore:** if Law.com Pro deals are meant to be *exempt*, the system needs a **signal** to recognise one — it cannot tell them apart today. Options for that signal:
- a specific product line that's always present on a Law.com Pro deal, or
- a flag/field on the opportunity or quote, or
- the "Law.com Pro" bundle parent being present.

## Concrete example — Skadden Arps (Q-197826)
| Product | Net | Role |
|---|---|---|
| Law.com (LAWM) | **$818k** | anchor → would drive code **1** |
| Law.com International (LWKM) | $171k | anchor |
| Radar, Compass, News Vault, GLL Advisers, China Law, LJP, NYLJ | rest | non-anchor |

By the current rule this deal = **code 1** (Law.com dominates). By Willie's view it should be **blank**. (Note: it had also picked up some stray legacy `3`s from before go-live — those have been cleaned up and the deal is currently set to `1` pending your decision.)

## What I need from you
Please pick one:

1. **Law.com Pro deals ARE coded** → confirm the rule (Skadden = 1) and we leave it; UAT stands.
2. **Law.com Pro deals are EXEMPT (no TCV)** → tell us **how to identify one** (product / flag / bundle), and we'll add that exemption to the engine so they're left blank automatically.

Either way I'll align the engine to your decision. Until then, comprehensive Law.com deals are the one area where the coding isn't reliably right.

---
*Separately, I'm investigating a technical edge case where the engine briefly derived `3` instead of `1` on this complex deal — that's a build issue I'll handle on our side and isn't part of this rule decision.*
