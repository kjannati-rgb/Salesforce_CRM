import json, subprocess, time, os, sys
SP = os.path.dirname(os.path.abspath(__file__))
os.chdir(SP)
ORG = 'LBR_PROD'
TEMPLATE = 'a1GPx000009lIKTMA2'

def sf(args):
    r = subprocess.run(['sf'] + args, capture_output=True, shell=True)
    return r.stdout.decode('utf-8', errors='replace')

def q(soql):
    out = sf(['data','query','-o',ORG,'--query',soql,'--json'])
    return json.loads(out[out.find('{'):]).get('result',{}).get('records',[])

import urllib.request
info = json.loads(sf(['org','display','--target-org',ORG,'--json']))['result']
BASE = info['instanceUrl']; TOKEN = info['accessToken']

def rest(method, path, body=None):
    req = urllib.request.Request(BASE + path, method=method,
        headers={'Authorization':'Bearer '+TOKEN,'Content-Type':'application/json'},
        data=json.dumps(body).encode() if body is not None else None)
    try:
        with urllib.request.urlopen(req) as r: return r.status, r.read().decode()
    except urllib.error.HTTPError as e: return e.code, e.read().decode()

# logo doc name by id
logo_by_id = {r['Id']: r['DeveloperName'] for r in q("SELECT Id, DeveloperName FROM Document WHERE DeveloperName LIKE 'Brand_Logo_%' OR DeveloperName='Centellic_Logo_2026'")}

def lead_brand(lines):
    best, bestv = None, None
    for l in lines:
        b = l.get('Brand__c'); n = l.get('SBQQ__NetTotal__c') or 0
        if b and (bestv is None or n > bestv): best, bestv = l, n
    if not best: return None, None
    fam = best.get('SBQQ__ProductFamily__c') or ''
    return ('Lexology Pro' if fam == 'Subs - Lexology Pro' else best.get('Brand__c')), best

def pick_quote(brand=None, family=None, extra=''):
    """find a quote whose lead brand matches"""
    if family:
        inner = f"SELECT SBQQ__Quote__c FROM SBQQ__QuoteLine__c WHERE SBQQ__ProductFamily__c='{family}'"
    else:
        inner = f"SELECT SBQQ__Quote__c FROM SBQQ__QuoteLine__c WHERE Brand__c='{brand}'"
    cands = q(f"SELECT Id, Name FROM SBQQ__Quote__c WHERE Id IN ({inner}) {extra} ORDER BY CreatedDate DESC LIMIT 8")
    for c in cands:
        lines = q(f"SELECT Brand__c, SBQQ__NetTotal__c, SBQQ__ProductFamily__c FROM SBQQ__QuoteLine__c WHERE SBQQ__Quote__c='{c['Id']}'")
        lb, _ = lead_brand(lines)
        want = 'Lexology Pro' if family == 'Subs - Lexology Pro' else brand
        if lb == want:
            return c
    return None

def run_scenario(key, quote, expect_logo, notes=''):
    qid, qname = quote['Id'], quote['Name']
    print(f"--- {key}: {qname} ({qid})")
    # heal lines (licence models) via anonymous apex
    apex = f"List<SBQQ__QuoteLine__c> ls=[SELECT Id FROM SBQQ__QuoteLine__c WHERE SBQQ__Quote__c='{qid}']; if(!ls.isEmpty()) update ls;"
    open('_heal.apex','w').write(apex)
    sf(['apex','run','-o',ORG,'-f',os.path.join(SP,'_heal.apex')])
    # stamp quote
    rest('PATCH', f'/services/data/v62.0/sobjects/SBQQ__Quote__c/{qid}', {'Order_Form_Brand_Logo_URL__c':'touch'})
    rec = q(f"SELECT Order_Form_Brand_Logo_URL__c, Order_Form_Terms_Label__c, Company_Entity_Name__c, Governing_Law_Text__c, Includes_API_Access__c, Account_Manager_Name__c FROM SBQQ__Quote__c WHERE Id='{qid}'")[0]
    url = rec.get('Order_Form_Brand_Logo_URL__c') or ''
    logo_id = url.split('id=')[1].split('&')[0] if 'id=' in url else None
    logo = logo_by_id.get(logo_id, logo_id)
    lines2 = q(f"SELECT SBQQ__ProductName__c, License_Model_Display__c FROM SBQQ__QuoteLine__c WHERE SBQQ__Quote__c='{qid}' ORDER BY SBQQ__NetTotal__c DESC LIMIT 4")
    lic = ['{}: {}'.format(l['SBQQ__ProductName__c'], (l.get('License_Model_Display__c') or 'BLANK')[:90]) for l in lines2]
    # render
    before = q(f"SELECT Id FROM SBQQ__QuoteDocument__c WHERE SBQQ__Quote__c='{qid}' ORDER BY CreatedDate DESC LIMIT 1")
    before_id = before[0]['Id'] if before else None
    model = json.dumps({'name':'OF scenario '+key,'quoteId':qid,'templateId':TEMPLATE,'outputFormat':'PDF','language':'en_US','paperSize':'Default'})
    st, body = rest('POST','/services/apexrest/SBQQ/ServiceRouter',{'saver':'SBQQ.QuoteDocumentAPI.Save','model':model})
    if st != 200:
        return {'key':key,'quote':qname,'logo':logo,'expect':expect_logo,'lic':lic,'pdf':None,'error':f'docgen {st}: {body[:120]}','notes':notes,'rec':rec}
    newdoc = None
    for _ in range(30):
        time.sleep(4)
        d = q(f"SELECT Id, SBQQ__DocumentId__c FROM SBQQ__QuoteDocument__c WHERE SBQQ__Quote__c='{qid}' ORDER BY CreatedDate DESC LIMIT 1")
        if d and d[0]['Id'] != before_id and d[0].get('SBQQ__DocumentId__c'):
            newdoc = d[0]; break
    if not newdoc:
        return {'key':key,'quote':qname,'logo':logo,'expect':expect_logo,'lic':lic,'pdf':None,'error':'doc never appeared','notes':notes,'rec':rec}
    # download
    req = urllib.request.Request(BASE + f"/services/data/v62.0/sobjects/Document/{newdoc['SBQQ__DocumentId__c']}/Body",
        headers={'Authorization':'Bearer '+TOKEN})
    pdf = f"scenario-{key}.pdf"
    with urllib.request.urlopen(req) as r: open(pdf,'wb').write(r.read())
    # cleanup
    rest('DELETE', f"/services/data/v62.0/sobjects/SBQQ__QuoteDocument__c/{newdoc['Id']}")
    rest('DELETE', f"/services/data/v62.0/sobjects/Document/{newdoc['SBQQ__DocumentId__c']}")
    ok = (expect_logo in (logo or '')) if expect_logo else True
    print(f"    logo={logo} expect~{expect_logo} match={ok} pdf={pdf}")
    return {'key':key,'quote':qname,'logo':logo,'expect':expect_logo,'lic':lic,'pdf':pdf,'error':None,'notes':notes,'rec':rec}

results = []
which = sys.argv[1] if len(sys.argv) > 1 else 'all'

BRANDS = [
    ('GAR','Brand_Logo_GAR'), ('GCR','Brand_Logo_GCR'), ('GIR','Brand_Logo_GIR'),
    ('GRR','Brand_Logo_GRR'), ('IAM','Brand_Logo_IAM'), ('WTR','Brand_Logo_WTR'),
    ('LACCA','Brand_Logo_LACCA'), ('LL','Brand_Logo_Latin_Lawyer'),
    ('Law.com','Brand_Logo_Law_com'), ('Lexology Panoramic','Brand_Logo_Lexology'),
    ('Lexology Index','Brand_Logo_Lexology_Index'),
]

if which in ('all','brands1'):
    for brand, logo in BRANDS[:6]:
        c = pick_quote(brand=brand)
        if c: results.append(run_scenario(brand.replace(' ','-').replace('.',''), c, logo))
        else: results.append({'key':brand,'error':'no lead quote found','pdf':None,'quote':'-','logo':'-','expect':logo,'lic':[],'notes':'','rec':{}})
if which in ('all','brands2'):
    for brand, logo in BRANDS[6:]:
        c = pick_quote(brand=brand)
        if c: results.append(run_scenario(brand.replace(' ','-').replace('.',''), c, logo))
        else: results.append({'key':brand,'error':'no lead quote found','pdf':None,'quote':'-','logo':'-','expect':logo,'lic':[],'notes':'','rec':{}})
if which in ('all','special'):
    c = pick_quote(family='Subs - Lexology Pro')
    if c: results.append(run_scenario('LexologyPRO', c, 'Brand_Logo_Lexology_PRO', 'Pro family override'))
    c = pick_quote(brand='MBL Seminars')
    if c: results.append(run_scenario('Centellic-fallback', c, 'Centellic_Logo_2026', 'unmapped brand -> Centellic'))
    # Key Account terms
    ka = q("SELECT Id, Name FROM SBQQ__Quote__c WHERE SBQQ__Opportunity2__r.Owner.UserRole.Name LIKE '%Global Enterprise Solutions%' AND SBQQ__LineItemCount__c > 0 ORDER BY CreatedDate DESC LIMIT 1")
    if ka: results.append(run_scenario('KeyAccount-terms', ka[0], None, 'expect Key Account terms label'))
    # API product
    api = q("SELECT Id, Name FROM SBQQ__Quote__c WHERE Id IN (SELECT SBQQ__Quote__c FROM SBQQ__QuoteLine__c WHERE API_Access__c = true) ORDER BY CreatedDate DESC LIMIT 1")
    if api: results.append(run_scenario('API-terms', api[0], None, 'expect API terms sentence'))
    # GHK entity
    ghk = q("SELECT Id, Name FROM SBQQ__Quote__c WHERE SBQQ__Opportunity2__r.Billing_Entity__c = 'GHK' AND SBQQ__LineItemCount__c > 0 ORDER BY CreatedDate DESC LIMIT 1")
    if ghk: results.append(run_scenario('GHK-entity', ghk[0], None, 'expect GHK entity block'))

json_path = 'sweep-results-' + which + '.json'
open(json_path,'w',encoding='utf-8').write(json.dumps(results, indent=1))
print('WROTE', json_path)
for r in results:
    print(r['key'], '|', r.get('quote'), '|', r.get('logo'), '|', 'ERR:'+str(r.get('error')) if r.get('error') else 'ok')
