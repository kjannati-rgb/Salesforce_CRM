"""Inline the training videos and stills into the Academy template as data URIs.
Usage: python build_academy.py <videos_dir> <stills_dir> <out.html>
The inflated HTML (~5 MB) is what gets published as the artifact; only the template is versioned."""
import base64, os, sys
here = os.path.dirname(os.path.abspath(__file__))
videos, stills, out = sys.argv[1:4]
html = open(os.path.join(here, 'payment-terms-academy.template.html'), encoding='utf-8').read()
def uri(path, mime):
    return f'data:{mime};base64,' + base64.b64encode(open(path, 'rb').read()).decode()
for key, fn in (('VIDEO_V1', 'v1_sales.mp4'), ('VIDEO_V2', 'v2_approvers.mp4'), ('VIDEO_V3', 'v3_finance.mp4')):
    html = html.replace('{{%s}}' % key, uri(os.path.join(videos, fn), 'video/mp4'))
for key, fn in (('IMG_PICKLIST', 'picklist.jpg'), ('IMG_BLOCK', 'block.jpg'), ('IMG_JUSTIFIED', 'justified.jpg'),
                ('IMG_APPROVALS', 'approvals.jpg'), ('IMG_PO', 'po.jpg'), ('IMG_REJECTED', 'rejected.jpg')):
    html = html.replace('{{%s}}' % key, uri(os.path.join(stills, fn), 'image/jpeg'))
assert '{{' not in html, 'unfilled placeholder'
open(out, 'w', encoding='utf-8').write(html)
print(out, round(os.path.getsize(out) / 1e6, 2), 'MB')
