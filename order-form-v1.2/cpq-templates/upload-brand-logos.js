// node upload-brand-logos.js --org <alias> --dir <folder-of-pngs>
// Uploads every <Brand>.png in --dir as Document Brand_Logo_<Brand> in the
// Order_Form_Brand_Assets folder, idempotent by DeveloperName (PATCH body if it exists).
// Prints the Document id per brand. Pairs with Order_Form_Brand_Logo__mdt rows, whose
// Logo_Document_Name__c must equal the DeveloperName printed here.
const { execSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const org = process.argv[process.argv.indexOf("--org") + 1];
const dir = process.argv[process.argv.indexOf("--dir") + 1];
if (!org || !dir) { console.error("Usage: node upload-brand-logos.js --org <alias> --dir <folder>"); process.exit(1); }
const info = JSON.parse(execSync(`sf org display --target-org ${org} --json`, { encoding: "utf8" })).result;
const isProd = !/sandbox/i.test(info.instanceUrl || "");
if (isProd && process.env.CONFIRM_PROD !== "YES") {
  console.error("Refusing to run against production without CONFIRM_PROD=YES");
  process.exit(1);
}
const API = `${info.instanceUrl}/services/data/v62.0`;
const H = { Authorization: `Bearer ${info.accessToken}`, "Content-Type": "application/json" };
const soql = async (q) => (await (await fetch(`${API}/query?q=${encodeURIComponent(q)}`, { headers: H })).json());

(async () => {
  let folder = (await soql(`SELECT Id FROM Folder WHERE DeveloperName = 'Order_Form_Brand_Assets' AND Type = 'Document' LIMIT 1`)).records[0];
  if (!folder) { console.error("Order_Form_Brand_Assets folder missing - run upload-brand-assets.js first"); process.exit(1); }

  for (const f of fs.readdirSync(dir).filter(x => x.toLowerCase().endsWith(".png")).sort()) {
    const key = path.basename(f, ".png");
    const dev = `Brand_Logo_${key}`;
    const body64 = fs.readFileSync(path.join(dir, f)).toString("base64");
    const doc = (await soql(`SELECT Id FROM Document WHERE DeveloperName = '${dev}' LIMIT 1`)).records[0];
    if (doc) {
      const res = await fetch(`${API}/sobjects/Document/${doc.Id}`, { method: "PATCH", headers: H, body: JSON.stringify({ Body: body64, IsPublic: true }) });
      console.log(`${dev} updated ${doc.Id} (${res.status})`);
    } else {
      const res = await fetch(`${API}/sobjects/Document`, { method: "POST", headers: H, body: JSON.stringify({
        Name: `Brand Logo ${key.replaceAll("_", " ")}`, DeveloperName: dev, FolderId: folder.Id,
        Type: "png", ContentType: "image/png", IsPublic: true, Body: body64 }) });
      const b = await res.json();
      if (!res.ok) { console.error(`${dev} create failed:`, JSON.stringify(b)); process.exit(1); }
      console.log(`${dev} created ${b.id}`);
    }
  }
})().catch(e => { console.error(e); process.exit(1); });
