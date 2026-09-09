"""Assemble the three Payment Terms training videos from captured KJDEV frames + edge-tts narration.
Output: videos/v1_sales.mp4, v2_approvers.mp4, v3_finance.mp4 (1280x720, H.264/AAC)."""
import os, subprocess, textwrap
from PIL import Image, ImageDraw, ImageFont
from mutagen.mp3 import MP3
import imageio_ffmpeg

ROOT = os.path.dirname(os.path.abspath(__file__))
FR, TTS = os.path.join(ROOT, 'frames'), os.path.join(ROOT, 'tts_edge')
OUT = os.path.join(ROOT, 'videos'); os.makedirs(OUT, exist_ok=True)
WORK = os.path.join(ROOT, 'video_work'); os.makedirs(WORK, exist_ok=True)
FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
W, H = 1280, 720
NAVY, GOLD, INK, PAPER = (11, 37, 69), (201, 162, 39), (30, 30, 30), (243, 243, 243)
F = lambda size, bold=False: ImageFont.truetype(r'C:\Windows\Fonts\segoeui%s.ttf' % ('b' if bold else ''), size)
PAD = 0.55  # seconds of silence after each narration segment

def cover_badge(im, right):
    """Paint over the browser-extension badge in the top-right of the captured page."""
    d = ImageDraw.Draw(im)
    for y0, y1, sy in ((4, 47, 24), (47, 60, 56)):
        d.rectangle((right - 52, y0, right - 1, y1), fill=im.getpixel((right - 70, sy)))
    return im

def _fit(im):
    avail_h = H - 64  # caption strip at the bottom
    s = min((W - 24) / im.width, (avail_h - 16) / im.height)
    im = im.resize((int(im.width * s), int(im.height * s)), Image.LANCZOS)
    canvas = Image.new('RGB', (W, H), PAPER)
    x = (W - im.width) // 2; y = 8 + (avail_h - 16 - im.height) // 2
    ImageDraw.Draw(canvas).rectangle((x - 1, y - 1, x + im.width, y + im.height), outline=(200, 200, 200))
    canvas.paste(im, (x, y))
    return canvas

def shot(name, box, right=1410):
    """Crop a captured frame to box=(x0,y0,x1,y1), fit onto a 1280x720 canvas."""
    im = Image.open(os.path.join(FR, name + '.png')).convert('RGB')
    im = cover_badge(im, right)
    return _fit(im.crop((box[0], box[1], min(box[2], im.width), min(box[3], im.height))))

import cv2, numpy as np
_TPL = cv2.imread(os.path.join(FR, 'seq3_approvals_po_08.png'), 0)[443:466, 44:150]  # 'Payment Information' header
def section(name, below, above=22, x1=940, y_override=None):
    """Crop from the Payment Information section header down `below` px."""
    if y_override is None:
        g = cv2.imread(os.path.join(FR, name + '.png'), 0)
        _, mx, _, loc = cv2.minMaxLoc(cv2.matchTemplate(g, _TPL, cv2.TM_CCOEFF_NORMED))
        assert mx > 0.8, (name, mx)
        y = loc[1]
    else:
        y = y_override
    return shot(name, (0, max(0, y - above), x1, y + below))

def caption(canvas, text, step=None):
    d = ImageDraw.Draw(canvas)
    d.rectangle((0, H - 64, W, H), fill=NAVY)
    d.rectangle((0, H - 64, W, H - 60), fill=GOLD)
    if step:
        d.text((28, H - 46), step, font=F(20, True), fill=GOLD)
        d.text((150, H - 47), text, font=F(24), fill='white')
    else:
        d.text((28, H - 47), text, font=F(24), fill='white')
    return canvas

def title_card(title, sub, audience):
    c = Image.new('RGB', (W, H), NAVY); d = ImageDraw.Draw(c)
    d.rectangle((80, 200, 92, 520), fill=GOLD)
    d.text((120, 190), 'PAYMENT TERMS ACADEMY', font=F(26, True), fill=GOLD)
    d.text((120, 240), title, font=F(64, True), fill='white')
    d.text((120, 340), sub, font=F(30), fill=(200, 210, 225))
    d.text((120, 470), audience, font=F(24), fill=(160, 175, 195))
    return c

def end_card(lines):
    c = Image.new('RGB', (W, H), NAVY); d = ImageDraw.Draw(c)
    d.rectangle((80, 150, 92, 570), fill=GOLD)
    y = 160
    for i, (t, big) in enumerate(lines):
        d.text((120, y), t, font=F(44 if big else 28, big), fill='white' if big else (200, 210, 225))
        y += 70 if big else 44
    return c

def slide(heading, bullets, kicker=None):
    c = Image.new('RGB', (W, H), 'white'); d = ImageDraw.Draw(c)
    d.rectangle((0, 0, W, 118), fill=NAVY); d.rectangle((0, 118, W, 124), fill=GOLD)
    d.text((60, 34), heading, font=F(44, True), fill='white')
    y = 170
    if kicker:
        d.text((60, y), kicker, font=F(28, True), fill=NAVY); y += 62
    for b in bullets:
        d.ellipse((66, y + 12, 80, y + 26), fill=GOLD)
        for j, line in enumerate(textwrap.wrap(b, 74)):
            d.text((100, y), line, font=F(28), fill=INK); y += 40
        y += 14
    d.text((60, H - 46), 'Payment Terms Academy  |  Centellic global payment terms process', font=F(18), fill=(120, 120, 120))
    return c

def build(vid, title, sub, audience, segments, end_lines):
    """segments: list of (seg_id, caption, step, [PIL frames])."""
    frames, concat, audio_inputs = [], [], []
    def add(img, dur):
        p = os.path.join(WORK, f'{vid}_{len(frames):03d}.png'); img.save(p); frames.append(p)
        concat.append(f"file '{p}'\nduration {dur:.3f}\n")
    add(title_card(title, sub, audience), 3.0)
    total = 3.0
    for seg_id, cap, step, imgs in segments:
        dur = MP3(os.path.join(TTS, seg_id + '.mp3')).info.length + PAD
        audio_inputs.append(os.path.join(TTS, seg_id + '.mp3'))
        each = dur / len(imgs)
        for im in imgs:
            add(caption(im.copy(), cap, step), each)
        total += dur
    add(end_card(end_lines), 4.0); total += 4.0
    concat.append(f"file '{frames[-1]}'\n")  # concat demuxer needs the last file repeated
    lst = os.path.join(WORK, f'{vid}.txt')
    open(lst, 'w', encoding='utf-8').write(''.join(concat).replace('\\', '/'))
    # audio: 3s lead silence, each segment padded, 4s tail
    inputs = []
    for a in audio_inputs: inputs += ['-i', a]
    fc = ''.join(f'[{i+1}:a]aresample=44100,apad=pad_dur={PAD}[a{i}];' for i in range(len(audio_inputs)))
    fc += ''.join(f'[a{i}]' for i in range(len(audio_inputs)))
    fc += f'concat=n={len(audio_inputs)}:v=0:a=1,adelay=3000,apad=pad_dur=4[aout]'
    out = os.path.join(OUT, vid + '.mp4')
    cmd = [FFMPEG, '-y', '-f', 'concat', '-safe', '0', '-i', lst] + inputs + [
        '-filter_complex', fc, '-map', '0:v', '-map', '[aout]',
        '-r', '12', '-c:v', 'libx264', '-preset', 'slow', '-crf', '27', '-pix_fmt', 'yuv420p', '-tune', 'stillimage',
        '-c:a', 'aac', '-b:a', '64k', '-ac', '1', '-shortest', '-movflags', '+faststart', out]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode: print(r.stderr[-3000:]); raise SystemExit(1)
    print(vid, f'{total:.1f}s', f'{os.path.getsize(out)/1e6:.2f} MB')

S, SEC = shot, section
FULL = 1568
HDR = (0, 70, 1410, 440)          # quote header + Approvals card (1410-wide captures)
HDR_F = (0, 90, 1410, 430)        # same on the full-width captures
APPROVE_PAGE = (500, 0, 1568, 230)
COMMENT_PAGE = (0, 0, 1100, 230)
V1 = [
 ('v1_s01', 'Payment terms live on the quote', 'Sales', [SEC('seq3_approvals_po_06', 290)]),
 ('v1_s02', 'Up to Net 30: yours to choose, nothing goes to Finance', 'Step 1', [SEC('seq1_small_block_00', 270, y_override=418), SEC('seq1_small_block_02', 330)]),
 ('v1_s03', 'Above 30 days: Net 45 / 60 normal; 75 / 90 / 120 exceptional', 'Step 2', [SEC('seq2_big_justify_07', 520)]),
 ('v1_s04', 'Under USD 10,000 ACV (GBP 7,500 / EUR 8,600): extended terms blocked', 'Rule 1', [SEC('seq1_small_block_05', 330), SEC('seq1_small_block_09', 330), SEC('seq1_small_block_11', 470, y_override=93), SEC('seq1_small_block_11', 470, y_override=93)]),
 ('v1_s05', 'GBP 7,500+ ACV: extended terms need a justification', 'Rule 2', [SEC('seq2_big_justify_08', 520), SEC('seq2_big_justify_10', 330), SEC('seq2_big_justify_14', 470)]),
 ('v1_s06', 'Justification, days and ACV (GBP): what Finance sees', 'Rule 2', [SEC('seq2_big_justify_17', 470), SEC('seq2_big_justify_17', 470), SEC('seq3_approvals_po_06', 290)]),
 ('v1_s07', 'Submit: Credit Control first, then Director of Financial Control', 'Approval', [S('seq3_approvals_po_05', HDR), S('seq5_approve_step1_11', HDR_F, FULL)]),
 ('v1_s08', 'Rejected? The reason comes back on the quote', 'Approval', [S('seq6_rejected_q3_04', (0, 70, 1330, 350), FULL), S('seq6_rejected_q3_06', (0, 60, 1050, 470), FULL)]),
]
V2 = [
 ('v2_s01', 'The request lands with Credit Control', 'Approvers', [S('seq3_approvals_po_03', (0, 70, 950, 450))]),
 ('v2_s02', 'Everything you need is on the request', 'Review', [S('seq3_approvals_po_03', (0, 70, 950, 450)), S('seq3_approvals_po_05', HDR)]),
 ('v2_s03', 'ACV (GBP) and days sit beside the terms', 'Review', [SEC('seq3_approvals_po_06', 290)]),
 ('v2_s04', 'Condition: set PO Required = Yes on the quote before approving', 'Condition', [SEC('seq3_approvals_po_08', 300), SEC('seq3_approvals_po_11', 300), SEC('seq3_approvals_po_14', 300), SEC('seq3_approvals_po_14', 300)]),
 ('v2_s05', 'Approve: moves to the Director of Financial Control automatically', 'Approve', [S('seq5_approve_step1_02', APPROVE_PAGE, FULL), S('seq5_approve_step1_04', COMMENT_PAGE, FULL), S('seq5_approve_step1_11', HDR_F, FULL)]),
 ('v2_s06', 'Reject: always say why; the comment goes back to the rep', 'Reject', [S('seq4_reject_page_03', COMMENT_PAGE, FULL), S('seq6_rejected_q3_04', (0, 70, 1330, 350), FULL)]),
 ('v2_s07', 'Two steps, no bypass, the whole trail stays on the quote', 'Director', [S('seq5_approve_step1_11', HDR_F, FULL)]),
]
V3 = [
 ('v3_s01', 'Two groups, split by quote type', 'Finance', [slide('Who approves what', [
     'Every finance approval on a quote now goes to one of two groups.',
     'The split is by the KIND of quote (new / renewal vs amendment / reissue), not by brand.',
     'Same rules, same thresholds, same chain for every brand, including ALM.'])]),
 ('v3_s02', 'Credit Control: all new and renewal quotes', 'Group 1', [slide('Credit Control', [
     'Samantha Law, Leslie Perry, Candice Goodpaster; Rahul Vadgama as UK backup.',
     'Every finance check on new and renewal quotes: extended payment terms (Net 45+), bad-debtor and finance-problem accounts, big deals, special terms, card thresholds.',
     'All brands, including ALM (the old ALM-only Credit Control rule is retired).'], kicker='New business and renewals')]),
 ('v3_s03', 'Finance - Amendments: amendment and reissue quotes only', 'Group 2', [slide('Finance - Amendments', [
     'Kevin, Chloe, Willie, Grace and Sherry.',
     'The same checks, on amendment and reissue quotes only.',
     'They never see a new quote.'], kicker='Amendments and reissues')]),
 ('v3_s04', 'What changed and how to maintain it', 'Summary', [slide('What changed', [
     'Net 30 and shorter no longer come to Finance at all (about 700 requests a year removed).',
     'Extended terms: Credit Control first, then the Director of Financial Control. Two steps, no bypass.',
     'Under USD 10,000 ACV (GBP 7,500 / EUR 8,600): extended terms are blocked at the quote, nothing to review.',
     'Membership is an admin change: holiday cover is a public-group edit, not a rule rebuild.'])]),
]
END = [('Full guide, simulator and FAQ:', False), ('Payment Terms Academy', True), ('', False),
       ('Questions: Kamyar Jannati, Head of Data and CRM', False), ('Finance policy: Lina Patel, Director of Financial Control', False)]
if __name__ == '__main__':
    import sys
    which = sys.argv[1:] or ['v1', 'v2', 'v3']
    if 'v1' in which: build('v1_sales', 'Choosing payment terms', 'What happens when you pick Net 45 or longer', 'For Sales  |  about 2 minutes', V1, END)
    if 'v2' in which: build('v2_approvers', 'Approving extended terms', 'The Credit Control and Director steps', 'For Credit Control and Finance  |  about 90 seconds', V2, END)
    if 'v3' in which: build('v3_finance', 'Who approves what', 'The two finance approver groups', 'For Finance  |  about 1 minute', V3, END)
