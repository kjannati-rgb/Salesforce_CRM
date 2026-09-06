import json, sys, re

KEYWORDS = re.compile(r'legal[_ ]?entity|entity|billing[_ ]?entity|company|region', re.I)

def scan(path, objname):
    with open(path, encoding='utf-8') as f:
        d = json.load(f)
    fields = d['result']['fields']
    hits = []
    for fld in fields:
        if KEYWORDS.search(fld['name']) or KEYWORDS.search(fld.get('label') or ''):
            hits.append(fld)
    print(f"\n{'='*80}\n{objname} — {len(fields)} fields total, {len(hits)} entity/company/region candidates\n{'='*80}")
    for fld in hits:
        ftype = fld['type']
        calc = fld.get('calculated', False)
        formula = fld.get('calculatedFormula')
        picks = [p['value'] for p in fld.get('picklistValues', []) if p.get('active')]
        print(f"\n- API: {fld['name']}")
        print(f"  Label: {fld['label']}")
        print(f"  Type: {ftype}{' (FORMULA)' if calc else ''}  Custom: {fld.get('custom')}  Updateable: {fld.get('updateable')}  Nillable: {fld.get('nillable')}")
        if formula:
            print(f"  Formula: {formula}")
        if picks:
            print(f"  Picklist ({len(picks)} active): {picks[:25]}")
        if ftype == 'reference':
            print(f"  References: {fld.get('referenceTo')}")

for path, obj in [
    ('describes/describe_opportunity.json', 'Opportunity'),
    ('describes/describe_user.json', 'User'),
    ('describes/describe_quote.json', 'SBQQ__Quote__c'),
    ('describes/describe_oli.json', 'OpportunityLineItem'),
]:
    scan(path, obj)
