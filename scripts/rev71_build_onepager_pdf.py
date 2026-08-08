# REV-71 — render the production-findings one-pager to a polished single-page PDF.
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.platypus import (SimpleDocTemplate, Paragraph, Spacer, Table,
                                TableStyle, HRFlowable)
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_LEFT

OUT = r"C:\sf-work\kjdev\audit-reports\REV71_Production_Findings_OnePager.pdf"

NAVY   = colors.HexColor("#1b2a4a")
ACCENT = colors.HexColor("#2e6da4")
GREEN  = colors.HexColor("#2e7d32")
AMBER  = colors.HexColor("#b26a00")
GREY   = colors.HexColor("#555555")
LIGHT  = colors.HexColor("#eef2f7")

styles = getSampleStyleSheet()
def S(name, **kw):
    base = kw.pop("parent", styles["Normal"])
    return ParagraphStyle(name, parent=base, **kw)

h_title = S("t", fontName="Helvetica-Bold", fontSize=16, textColor=NAVY, leading=19, spaceAfter=1)
h_sub   = S("s", fontName="Helvetica", fontSize=9.5, textColor=GREY, leading=12, spaceAfter=2)
lead    = S("l", fontName="Helvetica", fontSize=9.2, textColor=colors.black, leading=12.5, spaceAfter=4)
sect    = S("sec", fontName="Helvetica-Bold", fontSize=10.5, textColor=NAVY, leading=13, spaceBefore=5, spaceAfter=2)
body    = S("b", fontName="Helvetica", fontSize=8.8, textColor=colors.black, leading=11.3, spaceAfter=1.5)
bullet  = S("bu", parent=body, leftIndent=10, bulletIndent=1, spaceAfter=1.5)
small   = S("sm", fontName="Helvetica-Oblique", fontSize=7.8, textColor=GREY, leading=9.5)

doc = SimpleDocTemplate(OUT, pagesize=A4,
                        leftMargin=15*mm, rightMargin=15*mm,
                        topMargin=12*mm, bottomMargin=10*mm,
                        title="REV-71 Production Findings", author="Salesforce CRM")
E = []

E.append(Paragraph("REV-71 &ndash; ALM Invoice Code Automation", h_title))
E.append(Paragraph("Production findings &amp; decisions needed &nbsp;&middot;&nbsp; 13 June 2026 &nbsp;&middot;&nbsp; read-only analysis of LBR_PROD (nothing changed)", h_sub))
E.append(HRFlowable(width="100%", thickness=1.1, color=ACCENT, spaceBefore=2, spaceAfter=6))

E.append(Paragraph(
    "<b>In one line:</b> the automation is built, tested and ready in the sandbox. Before go-live, "
    "production data shows two of the original coding <i>rules</i> don&rsquo;t match how the business has "
    "actually been coding &mdash; three questions need a decision.", lead))

# Headline callout box
hl = Paragraph(
    "<b>Headline &mdash; the engine reproduces only 170 of 319 historically coded deals (53%).</b> "
    "The other 47% are inconsistent manual entries (the very problem this project removes) &mdash; but two "
    "patterns are too systematic to be error and reveal rules the spec got wrong.", body)
box = Table([[hl]], colWidths=[180*mm])
box.setStyle(TableStyle([
    ("BACKGROUND",(0,0),(-1,-1), LIGHT),
    ("BOX",(0,0),(-1,-1), 0.6, ACCENT),
    ("LEFTPADDING",(0,0),(-1,-1), 8), ("RIGHTPADDING",(0,0),(-1,-1), 8),
    ("TOPPADDING",(0,0),(-1,-1), 5), ("BOTTOMPADDING",(0,0),(-1,-1), 5),
]))
E.append(Spacer(1,3)); E.append(box); E.append(Spacer(1,5))

BULLET = "•"  # real bullet, present in the base font

E.append(Paragraph('<font color="#2e7d32">&#8226;&nbsp; CONFIRMED CORRECT &mdash; no discussion needed</font>', sect))
for t in [
    "<b>One code per deal</b> &mdash; 0 of 319 deals ever carry two codes.",
    "<b>Code lands on every line</b> of the group, including the secondary product.",
    "<b>Standalone sellable bundles</b> (Law.com Pro, Mid Market) are never coded &mdash; correct.",
    "<b>Bundle child lines</b> are essentially never coded (2 of 874) &mdash; matches the build.",
]:
    E.append(Paragraph(t, bullet, bulletText=BULLET))

E.append(Paragraph('<font color="#b26a00">&#8226;&nbsp; DECISIONS FOR CAYLA</font>', sect))
dec = [
    ("1. What makes a Law.com + International deal a &ldquo;1&rdquo; vs a &ldquo;3&rdquo;? <b>It is not price.</b> "
     "In all 113 such deals Law.com is the bigger line, yet 38% were coded <b>3</b>. Some other factor decides it "
     "(lead product? region? subscription type?). Until known, ~38% of these would be mis-coded."),
    ("2. <b>Code 2 (GLL) on deals with no GLL product</b> &mdash; 7 of 18. Is the rule broader than &ldquo;GLL present&rdquo;, "
     "or is this manual error?"),
    ("3. <b>102 deals coded on Law.com-<i>family</i> add-ons</b> (News Vault, Radar, Compass) with no core Law.com line. "
     "Should the whole Law.com family trigger code 1, not just the one core product?"),
]
for t in dec:
    E.append(Paragraph(t, bullet, bulletText=BULLET))

E.append(Paragraph('<font color="#2e6da4">&#8226;&nbsp; KNOCK-ON EFFECT (BACKFILL)</font>', sect))
E.append(Paragraph(
    "Because only 53% of existing codes reproduce, the historical codes <b>cannot be trusted as the target</b> for "
    "clean-up. A read-only audit is ready to list every wrong deal; remediation needs the rules locked <b>and</b> "
    "Integra&rsquo;s confirmation that changing a code mid-contract is safe.", body))

E.append(Paragraph("Recommendation", sect))
E.append(Paragraph(
    "<b>Don&rsquo;t change the engine yet</b> &mdash; it correctly applies the consistent rules, and bending it toward "
    "messy history would be wrong. Answer questions 1&ndash;3 and it&rsquo;s one contained change plus a re-test. For "
    "momentum, the engine can go live for the clean majority now via its built-in on/off switches, holding only the "
    "Law.com + International subset until question 1 is settled.", body))

E.append(Spacer(1,6))
E.append(HRFlowable(width="100%", thickness=0.5, color=colors.HexColor("#cccccc"), spaceAfter=3))
E.append(Paragraph(
    "Build status: 22/22 test matrix &middot; 11/11 automated regression suite &middot; production runbook complete &middot; "
    "monitoring deployed. &nbsp; Source: scripts/rev71_backfill_audit.apex (read-only).", small))

doc.build(E)
print("WROTE", OUT)
