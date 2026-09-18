"""Create a new version of Opportunity_Sync_Opportunity_Team from the org's CURRENTLY ACTIVE
version, adding one filter so the renewal team copy skips the Solutions Engineer role.
Everything else is copied verbatim. Usage: python sync_flow_exclude_se.py <org-alias> [--dry-run]
(metadata retrieve returns the LATEST version, which differs from the active one - hence Tooling API)"""
import json, subprocess, sys, urllib.request, urllib.error
ORG, DRY = sys.argv[1], '--dry-run' in sys.argv
FLOW, LOOKUP, ROLE = 'Opportunity_Sync_Opportunity_Team', 'Get_Previous_Opportunities_Team_Member', 'Solutions Engineer'
def sf(args):
    return json.loads(subprocess.run('sf ' + args + f' --target-org {ORG} --json', capture_output=True, text=True, shell=True).stdout)['result']
org = sf('org display'); base = org['instanceUrl'] + '/services/data/v62.0/tooling'
def call(method, path, body=None):
    req = urllib.request.Request(base + path, method=method, data=json.dumps(body).encode() if body else None,
                                 headers={'Authorization': 'Bearer ' + org['accessToken'], 'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req) as r: return json.loads(r.read() or b'{}')
    except urllib.error.HTTPError as e:
        sys.exit(f'{method} {path} -> HTTP {e.code}: {e.read().decode()[:1500]}')
act = sf(f'data query --use-tooling-api -q "SELECT Id, VersionNumber FROM Flow WHERE Definition.DeveloperName=\'{FLOW}\' AND Status=\'Active\'"')['records'][0]
md = call('GET', f"/sobjects/Flow/{act['Id']}")['Metadata']
def clean(o):
    if isinstance(o, dict): return {k: clean(v) for k, v in o.items() if v is not None and v != []}
    if isinstance(o, list): return [clean(v) for v in o]
    return o
md = clean(md)
lk = [e for e in md['recordLookups'] if e['name'] == LOOKUP][0]
if any(f.get('field') == 'TeamMemberRole' for f in lk['filters']):
    sys.exit(f'already patched (active v{act["VersionNumber"]}) - nothing to do')
lk['filters'].append({'field': 'TeamMemberRole', 'operator': 'NotEqualTo', 'value': {'stringValue': ROLE}})
lk['filterLogic'] = 'and'
md['description'] = (md.get('description') or '') + f' | {ROLE} role is deliberately NOT copied to the new opportunity (single-holder, deal-specific).'
print(f'active v{act["VersionNumber"]} -> lookup filters now:', [(f['field'], f['operator']) for f in lk['filters']])
if DRY: sys.exit('dry run - not created')
mx = sf(f'data query --use-tooling-api -q "SELECT MAX(VersionNumber) v FROM Flow WHERE Definition.DeveloperName=\'{FLOW}\'"')['records'][0]['v']
md['status'] = 'Active'
res = call('POST', '/sobjects/Flow', {'FullName': f'{FLOW}-{mx + 1}', 'Metadata': md})
print('created new version, Flow Id', res.get('id'))
