// Self-heal sweep: re-save subs quote lines on OPEN deals whose License_Model__c does not
// match the current rules - the authoritative before-save flow re-derives on save.
// Usage: node sweep-license-models.js --org <alias> [--apply]
const { execSync } = require("child_process");
const org = process.argv[process.argv.indexOf("--org") + 1];
const APPLY = process.argv.includes("--apply");
if (!org) { console.error("Usage: node sweep-license-models.js --org <alias> [--apply]"); process.exit(1); }
const info = JSON.parse(execSync(`sf org display --target-org ${org} --json`, { encoding: "utf8" })).result;
if (!/sandbox/i.test(info.instanceUrl) && process.env.CONFIRM_PROD !== "YES") {
  console.error("Refusing production without CONFIRM_PROD=YES"); process.exit(1);
}
console.log(`Target: ${info.username} @ ${info.instanceUrl} ${APPLY ? "(APPLY)" : "(dry run)"}`);
const API = `${info.instanceUrl}/services/data/v62.0`;
const H = { Authorization: `Bearer ${info.accessToken}`, "Content-Type": "application/json" };
const soqlAll = async (q) => {
  let out = [], res = await (await fetch(`${API}/query?q=${encodeURIComponent(q)}`, { headers: H })).json();
  if (!res.records) throw new Error("query failed: " + JSON.stringify(res).slice(0, 300));
  out.push(...res.records);
  while (!res.done) { res = await (await fetch(`${info.instanceUrl}${res.nextRecordsUrl}`, { headers: H })).json(); out.push(...res.records); }
  return out;
};

const LAWCOM = ["Subs - Law.com", "Subs - Law Journal Press"];
function expectedModel(r) {
  const family = r.SBQQ__Product__r.Family;
  if (LAWCOM.includes(family)) {
    const entity = r.SBQQ__Quote__r.SBQQ__Opportunity2__r ? r.SBQQ__Quote__r.SBQQ__Opportunity2__r.Billing_Entity__c : null;
    return ["ALM", "LLC"].includes(entity) ? "Limited Access" : "Benefiting Group";
  }
  return r.SBQQ__Product__r.License_Model__c || null;
}

(async () => {
  const rows = await soqlAll(
    "SELECT Id, License_Model__c, SBQQ__Product__r.Family, SBQQ__Product__r.License_Model__c, " +
    "SBQQ__Quote__r.SBQQ__Opportunity2__r.Billing_Entity__c " +
    "FROM SBQQ__QuoteLine__c WHERE (NOT SBQQ__Quote__r.SBQQ__Opportunity2__r.StageName LIKE 'Closed%') " +
    "AND SBQQ__Product__r.Family IN ('Subs - Specialist Platforms', 'Subs - Lexology Pro', " +
    "'Subs - Law.com', 'Subs - Law Journal Press', 'Subs - MBL Seminars')");
  const mismatched = rows.filter(r => (r.License_Model__c || null) !== expectedModel(r));
  console.log(`candidates: ${rows.length}, mismatched: ${mismatched.length}`);
  const byChange = {};
  for (const r of mismatched) {
    const k = `${r.License_Model__c || "(blank)"} -> ${expectedModel(r) || "(blank)"}`;
    byChange[k] = (byChange[k] || 0) + 1;
  }
  for (const [k, n] of Object.entries(byChange).sort((a, b) => b[1] - a[1])) console.log(`  ${n}  ${k}`);
  if (!APPLY) { console.log("dry run - re-run with --apply to heal"); return; }

  // small batches: 200-line transactions drag the CPQ line triggers past governor limits
  const SIZE = 25;
  let healed = 0, failed = 0;
  for (let i = 0; i < mismatched.length; i += SIZE) {
    const batch = mismatched.slice(i, i + SIZE).map(r => ({ attributes: { type: "SBQQ__QuoteLine__c" }, Id: r.Id, License_Model__c: null }));
    const res = await fetch(`${API}/composite/sobjects`, { method: "PATCH", headers: H, body: JSON.stringify({ allOrNone: false, records: batch }) });
    const results = await res.json();
    for (const r of results) { if (r.success) healed++; else { failed++; if (failed <= 3) console.error("  fail:", JSON.stringify(r.errors).slice(0, 250)); } }
    if ((i / SIZE) % 20 === 0 || i + SIZE >= mismatched.length) console.log(`  progress: healed ${healed}, failed ${failed}`);
  }
  console.log(`DONE: healed ${healed}, failed ${failed}`);
})().catch(e => { console.error(e); process.exit(1); });
