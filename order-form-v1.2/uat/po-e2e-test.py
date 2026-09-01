import json, subprocess, time, os, urllib.request, re
import pypdfium2 as pdfium
SP = os.path.dirname(os.path.abspath(__file__)); os.chdir(SP)
ORG = 'LBR_PROD'; TEMPLATE = 'a1GPx000009lIKTMA2'

def sf(args):
    r = subprocess.run(['sf'] + args, capture_output=True, shell=True)
    return r.stdout.decode('utf-8', errors='replace')

def q(soql):
    out = sf(['data','query','-o',ORG,'--query',soql,'--json'])
    return json.loads(out[out.find('{'):]).get('result',{}).get('records',[])

info = json.loads(sf(['org','display','--target-org',ORG,'--json']))['result']
BASE = info['instanceUrl']; TOKEN = info['accessToken']

def rest(method, path, body=None):
    req = urllib.request.Request(BASE + path, method=method,
        headers={'Authorization':'Bearer '+TOKEN,'Content-Type':'application/json'},
        data=json.dumps(body).encode() if body is not None else None)
    try:
        with urllib.request.urlopen(req) as r: return r.status, r.read().decode()
    except urllib.error.HTTPError as e: return e.code, e.read().decode()

def render(qid, pdf):
    before = q(f"SELECT Id FROM SBQQ__QuoteDocument__c WHERE SBQQ__Quote__c='{qid}' ORDER BY CreatedDate DESC LIMIT 1")
    before_id = before[0]['Id'] if before else None
    model = json.dumps({'name':'PO e2e','quoteId':qid,'templateId':TEMPLATE,'outputFormat':'PDF','language':'en_US','paperSize':'Default'})
    st, body = rest('POST','/services/apexrest/SBQQ/ServiceRouter',{'saver':'SBQQ.QuoteDocumentAPI.Save','model':model})
    assert st == 200, f'docgen {st}: {body[:150]}'
    newdoc = None
    for _ in range(30):
        time.sleep(4)
        d = q(f"SELECT Id, SBQQ__DocumentId__c FROM SBQQ__QuoteDocument__c WHERE SBQQ__Quote__c='{qid}' ORDER BY CreatedDate DESC LIMIT 1")
        if d and d[0]['Id'] != before_id and d[0].get('SBQQ__DocumentId__c'):
            newdoc = d[0]; break
    assert newdoc, 'doc never appeared'
    req = urllib.request.Request(BASE + f"/services/data/v62.0/sobjects/Document/{newdoc['SBQQ__DocumentId__c']}/Body",
        headers={'Authorization':'Bearer '+TOKEN})
    with urllib.request.urlopen(req) as r: open(pdf,'wb').write(r.read())
    rest('DELETE', f"/services/data/v62.0/sobjects/SBQQ__QuoteDocument__c/{newdoc['Id']}")
    rest('DELETE', f"/services/data/v62.0/sobjects/Document/{newdoc['SBQQ__DocumentId__c']}")
    doc = pdfium.PdfDocument(pdf)
    text = re.sub(r'\s+', ' ', ''.join(doc[i].get_textpage().get_text_range() for i in range(len(doc))))
    doc.close()
    return text

CASES = [
    # (label, quote name, must_contain, must_not_contain)
    ('A: flagged account + blank PO', 'Q-223067',
        ['Yes - your organisation requires a PO on invoices', '{{*PO_Number_es_:signer1}}'],
        ['radio(Yes)', 'radio(No)', 'showif']),
    ('B: unflagged + blank PO', 'Q-222823',
        ['radio(Yes)', 'radio(No)', 'showif(PO_Required=Yes)'],
        ['your organisation requires a PO']),
    ('C: quote already holds a PO', 'Q-222726',
        ['Yes (PO number below)'],
        ['radio(Yes)', 'radio(No)', 'showif', '{{*PO_Number_es_:signer1}}']),
]
allpass = True
for label, name, must, mustnot in CASES:
    rec = q(f"SELECT Id, SBQQ__Account__r.PO_Required__c, PO_Number__c FROM SBQQ__Quote__c WHERE Name='{name}'")[0]
    print(f"--- {label} ({name}) account-flag={rec['SBQQ__Account__r']['PO_Required__c']} PO={rec['PO_Number__c']}")
    # heal quote (formulas need no save, but stamped fields might; touch anyway for realism)
    text = render(rec['Id'], f'po-test-{name}.pdf')
    for m in must:
        ok = m in text
        allpass &= ok
        print(('  PASS  ' if ok else '  FAIL  ') + 'contains: ' + m)
    for m in mustnot:
        ok = m not in text
        allpass &= ok
        print(('  PASS  ' if ok else '  FAIL  ') + 'absent:   ' + m)
print('ALL PASS' if allpass else 'FAILURES PRESENT')
