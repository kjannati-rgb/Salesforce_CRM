// node seed-license-models.js --org KJDEV
// Seeds Product2.License_Model__c for the 'Subs - Specialist Platforms' family per
// Kam's 2026-08-14/18 rulings: the licence-type LABEL from the product name is stored
// on the product (Individual/Team/Office/Group/Firmwide/Bespoke License). The display
// formula prints these labels verbatim (no legal sentence); the four legal wordings
// remain reserved for the Lexology Pro / Law.com families (seeded separately).
// Matching is by NAME SUFFIX PATTERN, which is separator-agnostic (catches the en-dash
// "GCR – Standard – Individual License" record). Print Copies and the odd one-off subs
// (Subscription ART etc.) are intentionally left blank.
// Idempotent: re-running rewrites the same values. CONFIRM_PROD guard for Phase 6.
const { execSync } = require("child_process");

const org = process.argv[process.argv.indexOf("--org") + 1];
if (!org) { console.error("Usage: node seed-license-models.js --org <alias>"); process.exit(1); }
const info = JSON.parse(execSync(`sf org display --target-org ${org} --json`, { encoding: "utf8" })).result;
const isProd = info.id.startsWith("00D6g0000081IOg") || !/sandbox/i.test(info.instanceUrl || "");
if (isProd && process.env.CONFIRM_PROD !== "YES") {
  console.error("Refusing to run against production without CONFIRM_PROD=YES");
  process.exit(1);
}
console.log(`Target: ${info.username} @ ${info.instanceUrl}`);
const API = `${info.instanceUrl}/services/data/v62.0`;
const H = { Authorization: `Bearer ${info.accessToken}`, "Content-Type": "application/json" };

const LABELS = ["Individual License", "Team License", "Office License", "Group License", "Firmwide License", "Bespoke License"];
// Lexology Pro (Kam 2026-08-18): legacy block pricing is history - the licence model NOW is
// Benefiting Group for all person licences. Machine-access APIs stay blank.
const LEXOLOGY_API_SKIP = ["Lexology PRO - Intelligence API", "Lexology PRO - Scanner API"];

function labelFor(p) {
  if (p.Family === "Subs - Lexology Pro") {
    return LEXOLOGY_API_SKIP.includes(p.Name) ? null : "Benefiting Group";
  }
  return LABELS.find(l => p.Name.includes(l)) || null;
}

(async () => {
  const res = await fetch(`${API}/query?q=${encodeURIComponent(
    "SELECT Id, Name, Family, License_Model__c FROM Product2 WHERE IsActive = true AND Family IN ('Subs - Specialist Platforms', 'Subs - Lexology Pro')")}`, { headers: H });
  const products = (await res.json()).records || [];
  console.log(`${products.length} active products across seeded families`);
  let set = 0, skipped = 0, unchanged = 0;
  for (const p of products) {
    const label = labelFor(p);
    if (!label) { console.log(`  skip (no licence label): ${p.Name}`); skipped++; continue; }
    if (p.License_Model__c === label) { unchanged++; continue; }
    const r = await fetch(`${API}/sobjects/Product2/${p.Id}`, { method: "PATCH", headers: H, body: JSON.stringify({ License_Model__c: label }) });
    if (r.status === 204) { set++; }
    else { console.error(`  FAILED ${p.Name}:`, (await r.text()).slice(0, 200)); }
  }
  console.log(`seeded: ${set}, already correct: ${unchanged}, skipped (no label): ${skipped}`);
})().catch(e => { console.error(e); process.exit(1); });
