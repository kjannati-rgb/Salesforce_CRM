import json, glob, csv, os

# Classify where the entity reference appears in each report describe:
# detail columns, filters (with value), row/column groupings, or aggregates.
NEEDLES = ('LBR_Legal_Entity', 'Owner_Company_Name')

with open('reports/report_inventory.json', encoding='utf-8') as f:
    inv = {r['Id']: r for r in json.load(f)['result']['records']}

rows = []
scanned = 0
for path in glob.glob('reports/describes/*.json'):
    rid = os.path.basename(path)[:-5]
    with open(path, encoding='utf-8') as f:
        raw = f.read()
    scanned += 1
    if not any(n in raw for n in NEEDLES):
        continue
    d = json.loads(raw)
    md = d.get('reportMetadata', {})
    where = []
    filter_values = []
    for c in md.get('detailColumns') or []:
        if any(n in c for n in NEEDLES):
            where.append(f'column:{c}')
    for flt in md.get('reportFilters') or []:
        col = flt.get('column', '')
        if any(n in col for n in NEEDLES):
            where.append(f'filter:{col} {flt.get("operator")} "{flt.get("value")}"')
            filter_values.append(str(flt.get('value')))
    for g in (md.get('groupingsDown') or []) + (md.get('groupingsAcross') or []):
        if any(n in (g.get('name') or '') for n in NEEDLES):
            where.append(f'grouping:{g.get("name")}')
    for agg in md.get('aggregates') or []:
        if any(n in agg for n in NEEDLES):
            where.append(f'aggregate:{agg}')
    # bucket fields / cross filters / custom summary formulas can also hold refs
    for b in md.get('buckets') or []:
        src = json.dumps(b)
        if any(n in src for n in NEEDLES):
            where.append(f'bucket:{b.get("developerName", b.get("label", "?"))}')
    for cf in md.get('crossFilters') or []:
        src = json.dumps(cf)
        if any(n in src for n in NEEDLES):
            where.append('crossFilter')
    if not where:
        where.append('other(raw-json hit: CSF or embedded ref)')
    meta = inv.get(rid, {})
    rows.append({
        'ReportId': rid,
        'Name': meta.get('Name'),
        'DeveloperName': meta.get('DeveloperName'),
        'Folder': meta.get('FolderName'),
        'LastRunDate': meta.get('LastRunDate'),
        'ReportType': (md.get('reportType') or {}).get('type'),
        'Where': ' | '.join(where),
        'FilterValues': '; '.join(filter_values),
    })

rows.sort(key=lambda r: (r['Folder'] or '', r['Name'] or ''))
with open('reports/affected-reports.csv', 'w', newline='', encoding='utf-8') as f:
    w = csv.DictWriter(f, fieldnames=['ReportId','Name','DeveloperName','Folder','LastRunDate','ReportType','Where','FilterValues'])
    w.writeheader(); w.writerows(rows)

print(f'scanned {scanned} describes; {len(rows)} affected reports')
from collections import Counter
print('\nBy folder (top 30):')
for folder, n in Counter(r['Folder'] for r in rows).most_common(30):
    print(f'  {n:4d}  {folder}')
print('\nFilter values seen:')
for v, n in Counter(v for r in rows for v in r['FilterValues'].split('; ') if v).most_common(20):
    print(f'  {n:4d}  {v}')
