# Payment terms training videos — scripts & voiceover transcripts

Companion to the **Payment Terms Academy** page. Three short videos, real Salesforce screens
(captured in the KJDEV sandbox on the same pages Sales and Finance use in production), narrated
with a British neural voice. Transcripts are word-for-word — reuse them
as captions or for a live walkthrough.

---

## Video 1 — "Choosing payment terms" (Sales, ~95 seconds)

**Screen:** a quote's Payment Information section.

> Payment terms now live in one place on the quote, and the system does the policy work for you.
> Here's what happens.
>
> **[Payment Information section]** Immediate payment is the default, and anything up to Net 30
> is yours to choose — pick it, save, done. Nothing goes to Finance.
>
> **[Picklist open]** Above 30 days is where the process starts. Net 45 and Net 60 are the
> normal extended terms; Net 75, 90 and 120 exist only for the genuinely exceptional case.
>
> **[Small deal, Net 45, block message]** First rule: the deal has to be big enough. Under ten
> thousand dollars a year — that's seven and a half thousand pounds, or eight thousand six
> hundred euros — extended terms simply aren't available. The quote won't save, the message
> tells you why, and there is no approval route. Pick Net 30 or shorter and move on.
>
> **[Big deal, Net 45, justification message]** On a larger deal, extended terms can be
> considered — but Finance needs your case. Save without a justification and it stops you.
>
> **[Justification typed, saved]** Write a short justification: deal size, contract length, the
> company, and anything you know about their credit. Save, and it's accepted. Notice the two
> read-only fields underneath — the days, and the annualised contract value in pounds — that's
> exactly what Finance will see.
>
> **[Approvals list after submit]** Submit for approval as normal. The request goes to Credit
> Control first, then to the Director of Financial Control — you can watch it move through the
> steps right here on the quote.
>
> **[Rejected approval with comment]** If Finance says no, the reason comes back with it. Read
> the comment, adjust the terms or the deal, and resubmit. No Teams messages, no chasing.

---

## Video 2 — "Approving extended terms" (Credit Control & Finance, ~90 seconds)

**Screen:** an approval record, then the quote under review.

> When a rep asks for extended terms, the request lands with Credit Control. Here's the whole
> job.
>
> **[Approval record]** Everything you need is on the request: the quote, the terms asked for,
> and the rep's justification. Open the quote for the value and the account.
>
> **[Quote under review — read-only fields]** On the quote, the annualised value in pounds and
> the number of days are right beside the terms, so you're comparing like with like whatever
> the currency of the deal.
>
> **[PO Required set to Yes]** If your answer is "yes — but only with a purchase order", you can
> make that a condition. Set PO Required to Yes on the quote before you approve. The signing
> flow will then refuse to complete until the customer enters their PO number. Nothing to chase
> after signature.
>
> **[Approve]** Approve, and the request moves automatically to the Director of Financial
> Control for the final decision. You're done.
>
> **[Reject with comment]** Reject, and always say why — your comment goes straight back to the
> rep on the quote. "Credit exposure too high for 60 days; offer Net 45" is a complete answer.
>
> **[Director's step]** The Director sees only what Credit Control has already approved. Two
> steps, no bypass, and the whole trail stays on the quote.

---

## Video 3 — "Who approves what" (Finance, ~50 seconds, slides)

> Two groups now handle every finance approval on a quote, and the split is by the kind of
> quote — not by brand.
>
> **[Slide: Credit Control]** Credit Control — Samantha, Leslie and Candice, with Rahul as UK
> backup — takes every check on new and renewal quotes: extended payment terms, bad-debtor and
> finance-problem accounts, big deals, special terms and card thresholds. All brands, including
> ALM.
>
> **[Slide: Finance – Amendments]** Kevin, Chloe, Willie, Grace and Sherry take the same checks
> on amendment and reissue quotes only. They never see a new quote.
>
> **[Slide: what changed]** Net 30 and shorter no longer come to Finance at all — roughly seven
> hundred requests a year that had no reason to be there. Extended terms go to Credit Control and
> then the Director. And membership is a simple admin change: holiday cover is a group edit, not
> a rebuild.

---

## Recording notes

- Frames captured 9 Sep 2026 in KJDEV on the real Lightning record pages (Draft / Pending /
  Approved) via the Claude-in-Chrome GIF recorder, cropped to the Payment Information section or
  the Approvals card (OpenCV template match on the section header); narration Microsoft
  neural voice "en-GB-RyanNeural" via edge-tts (the ElevenLabs "George" quota ran out after the
  first six segments; on the corporate network edge-tts needs `truststore` for the proxy CA).
- Build: `scratchpad/build_videos.py` (frames + tts_edge mp3s -> videos/*.mp4, 1280x720 H.264,
  title/end cards, caption strip per segment). Rendered files live in `videos/` next to this doc.
- Academy page: `payment-terms-academy.template.html` + `build_academy.py` inline the three mp4s
  and six stills as data URIs for the artifact (artifact-hosted copy is ~5 MB, not versioned).
- Demo quotes: Q-211556 (GBP 5k, the block) and Q-211562 (24-month GBP 20k = GBP 10k ACV, the
  justification and approval flow).
