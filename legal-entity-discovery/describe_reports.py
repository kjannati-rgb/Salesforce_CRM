import json, os, sys, time, urllib.request, urllib.error
from concurrent.futures import ThreadPoolExecutor, as_completed

# Dead corporate proxy vars hang all outbound requests on this machine — strip them.
for v in ('HTTP_PROXY', 'HTTPS_PROXY', 'http_proxy', 'https_proxy', 'ALL_PROXY', 'all_proxy'):
    os.environ.pop(v, None)
urllib.request.install_opener(urllib.request.build_opener(urllib.request.ProxyHandler({})))

# Read-only: Analytics REST describe (GET) for each report run in last 12 months.
with open('evidence/org_auth.json', encoding='utf-8') as f:
    auth = json.load(f)['result']
TOKEN = auth['accessToken']
BASE = auth['instanceUrl'].rstrip('/')
API = 'v62.0'

with open('reports/report_inventory.json', encoding='utf-8') as f:
    inv = json.load(f)['result']['records']
targets = [r for r in inv if (r.get('LastRunDate') or '') >= '2025-07-03']
print(f'{len(targets)} reports to describe (of {len(inv)} total)', flush=True)

os.makedirs('reports/describes', exist_ok=True)
done = set(fn[:-5] for fn in os.listdir('reports/describes'))
targets = [r for r in targets if r['Id'] not in done]
print(f'{len(targets)} remaining after resume-skip', flush=True)

failures = []

def describe(rid):
    path = f'reports/describes/{rid}.json'
    url = f'{BASE}/services/data/{API}/analytics/reports/{rid}/describe'
    req = urllib.request.Request(url, headers={'Authorization': f'Bearer {TOKEN}'})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                data = resp.read()
            with open(path, 'wb') as f:
                f.write(data)
            return None
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 503) and attempt < 2:
                time.sleep(3 * (attempt + 1)); continue
            return (rid, f'HTTP {e.code}: {e.read()[:150]}')
        except Exception as e:
            if attempt < 2:
                time.sleep(2); continue
            return (rid, repr(e)[:150])

count = 0
with ThreadPoolExecutor(max_workers=6) as ex:
    futs = {ex.submit(describe, r['Id']): r['Id'] for r in targets}
    for fut in as_completed(futs):
        res = fut.result()
        count += 1
        if res:
            failures.append(res)
        if count % 250 == 0:
            print(f'{count}/{len(targets)} done, {len(failures)} failures', flush=True)
        time.sleep(0.05)  # modest throttle on the collector side

print(f'FINISHED: {count} described, {len(failures)} failures', flush=True)
with open('reports/describe_failures.json', 'w', encoding='utf-8') as f:
    json.dump(failures, f, indent=1)
