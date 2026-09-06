# Phase 2/3 resolver - maps every report column/filter token to Object + Field
# Read-only: consumes raw/ and describes/ JSON, emits out/dictionary_data.json
import json, os

BASE = os.path.dirname(os.path.abspath(__file__))

def load(p):
    return json.load(open(os.path.join(BASE, p), encoding='utf-8'))

analytics = load('raw/analytics_describe.json')
rm = analytics['reportMetadata']
ext = analytics['reportExtendedMetadata']['detailColumnInfo']
cdfs = rm.get('customDetailFormula') or {}

DESCRIBES = {}
for f in os.listdir(os.path.join(BASE, 'describes')):
    d = load('describes/' + f)['result']
    DESCRIBES[d['name']] = d

def fields_of(obj):
    return DESCRIBES[obj]['fields']

def find_field(obj, api):
    for f in fields_of(obj):
        if f['name'].lower() == api.lower():
            return f
    return None

def find_rel(obj, rel):
    for f in fields_of(obj):
        if f.get('relationshipName') and f['relationshipName'].lower() == rel.lower():
            return f
    return None

BASE_ALIAS = {
    'Opportunity': 'Opportunity',
    'OpportunityLineItem': 'OpportunityLineItem',
    'OpportunityLineItemSchedule': 'OpportunityLineItemSchedule',
}

def pick_ref(field, next_seg=None):
    """Choose target object from referenceTo. Prefer non-Group for polymorphic."""
    refs = field.get('referenceTo') or []
    if len(refs) == 1:
        return refs[0], None
    pruned = [r for r in refs if r not in ('Group',)]
    if len(pruned) == 1:
        return pruned[0], 'polymorphic lookup (%s) - resolved to %s' % ('/'.join(refs), pruned[0])
    # ambiguous - try next segment as hint
    return (pruned[0] if pruned else refs[0]), 'polymorphic lookup (%s) - assumed %s' % ('/'.join(refs), pruned[0] if pruned else refs[0])

def resolve(token):
    """Return dict: source_object, field_api, field(meta), notes(list), converted(bool)."""
    notes = []
    if token in cdfs:
        c = cdfs[token]
        return {'source_object': 'Report-defined', 'field_api': token, 'field': None,
                'notes': ['Row-level formula, label "%s", returns %s' % (c['label'], c['formulaType'])],
                'formula_text': c['formula'], 'converted': False}
    segs = token.split('.')
    converted = False
    if segs[-1] == 'CONVERT':
        converted = True
        segs = segs[:-1]
    if segs[0] not in BASE_ALIAS:
        return {'source_object': 'UNRESOLVED', 'field_api': token, 'field': None,
                'notes': ['Unknown base alias'], 'formula_text': '', 'converted': converted}
    obj = BASE_ALIAS[segs[0]]
    # walk intermediate relationship segments
    for seg in segs[1:-1]:
        f = find_field(obj, seg)
        if f and f['type'] == 'reference':
            nxt, note = pick_ref(f)
            if note: notes.append(note)
            obj = nxt
            continue
        f = find_rel(obj, seg)
        if f:
            nxt, note = pick_ref(f)
            if note: notes.append(note)
            obj = nxt
            continue
        return {'source_object': 'UNRESOLVED', 'field_api': token, 'field': None,
                'notes': ['Cannot traverse segment "%s" from %s' % (seg, obj)],
                'formula_text': '', 'converted': converted}
    leaf = segs[-1]
    f = find_field(obj, leaf)
    if not f:
        return {'source_object': 'UNRESOLVED', 'field_api': token, 'field': None,
                'notes': ['Field "%s" not found on %s' % (leaf, obj)],
                'formula_text': '', 'converted': converted}
    return {'source_object': obj, 'field_api': f['name'], 'field': f,
            'notes': notes, 'formula_text': f.get('calculatedFormula') or '', 'converted': converted}

def fmt_len(f):
    t = f['type']
    if t in ('string', 'textarea', 'phone', 'email', 'url', 'picklist', 'multipicklist', 'encryptedstring', 'id', 'reference'):
        return str(f.get('length') or '')
    if t in ('double', 'currency', 'percent', 'int'):
        p, s = f.get('precision'), f.get('scale')
        if p is not None:
            return '%s.%s' % (p, s if s is not None else 0)
    return ''

def active_picks(f):
    return [(v['value'], v.get('label'), v.get('defaultValue', False))
            for v in (f.get('picklistValues') or []) if v.get('active')]

# ---- build column rows ----
col_rows = []
picklist_sheet = []
for i, token in enumerate(rm['detailColumns'], 1):
    info = ext.get(token, {})
    r = resolve(token)
    f = r['field']
    notes = list(r['notes'])
    row = {
        'n': i, 'label': info.get('label', ''), 'token': token,
        'source_object': r['source_object'], 'field_api': r['field_api'],
        'field_label': f['label'] if f else ('Row-level formula' if r['source_object'] == 'Report-defined' else ''),
        'data_type': f['type'] if f else (cdfs[token]['formulaType'] if token in cdfs else info.get('dataType', '')),
        'len_prec': fmt_len(f) if f else '',
        'custom': ('Yes' if f['custom'] else 'No') if f else ('n/a' if r['source_object'] == 'Report-defined' else ''),
        'formula': ('Yes' if (f and f.get('calculated')) or token in cdfs else 'No'),
        'formula_text': r['formula_text'],
        'picklist': 'No', 'picklist_values': '', 'lookup_to': '', 'help_text': '', 'notes': '',
    }
    if f:
        if f['type'] in ('picklist', 'multipicklist'):
            row['picklist'] = 'Yes'
            vals = active_picks(f)
            if len(vals) <= 15:
                row['picklist_values'] = '; '.join(v[0] for v in vals)
            else:
                row['picklist_values'] = 'see Picklists sheet - %d values' % len(vals)
                for v in vals:
                    picklist_sheet.append((r['source_object'], f['name'], v[0], 'Yes', 'Yes' if v[2] else 'No'))
        if f['type'] == 'reference':
            row['lookup_to'] = ', '.join(f.get('referenceTo') or [])
        row['help_text'] = f.get('inlineHelpText') or ''
        # ACM note
        if f['type'] == 'currency':
            if r['converted']:
                notes.append('converted (ACM) - report converts to report currency GBP')
            else:
                notes.append('record-currency amount - depends on record CurrencyIsoCode')
        if f['name'] == 'CurrencyIsoCode':
            notes.append('record currency code - drives interpretation of record-currency amounts')
        # analytics label vs field label check
        an_label = info.get('label', '')
        tail = an_label.split(': ')[-1] if ': ' in an_label else an_label
        if f['label'] not in (an_label, tail) and tail != f['label']:
            notes.append('report column label differs from field label "%s"' % f['label'])
    if r['converted']:
        row['field_api'] = row['field_api']  # field name already clean; token retains .CONVERT
    row['notes'] = '. '.join(notes)
    col_rows.append(row)

# ---- filters ----
flt_rows = []
for i, flt in enumerate(rm.get('reportFilters', []), 1):
    token = flt['column']
    r = resolve(token)
    notes = list(r['notes'])
    if r['field'] and r['field']['type'] in ('picklist', 'multipicklist'):
        notes.append('picklist filter')
    flt_rows.append({
        'n': i, 'token': token, 'source_object': r['source_object'],
        'field_api': r['field_api'], 'operator': flt['operator'],
        'value': flt['value'], 'notes': '. '.join(notes),
    })

out = {
    'columns': col_rows,
    'filters': flt_rows,
    'picklists': picklist_sheet,
    'meta': {
        'reportType': rm['reportType'],
        'scope': rm.get('scope'),
        'currency': rm.get('currency'),
        'booleanFilter': rm.get('reportBooleanFilter'),
        'standardDateFilter': rm.get('standardDateFilter'),
        'cdf': cdfs,
    },
}
os.makedirs(os.path.join(BASE, 'out'), exist_ok=True)
json.dump(out, open(os.path.join(BASE, 'out/dictionary_data.json'), 'w', encoding='utf-8'), indent=1)

unres = [r for r in col_rows + flt_rows if r['source_object'] == 'UNRESOLVED']
print('columns:', len(col_rows), 'filters:', len(flt_rows), 'UNRESOLVED:', len(unres))
for r in unres:
    print('  UNRESOLVED:', r['token'], r.get('notes'))
from collections import Counter
print(Counter(r['source_object'] for r in col_rows))
