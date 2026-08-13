// node upload-brand-assets.js --org KJDEV --logo <path-to-png> [--watermark <path-to-png>]
// Uploads the Centellic logo (and optionally the DRAFT watermark) as externally-available
// Documents in a public folder, idempotent by document name. Prints ids/URLs for the template.
const { execSync } = require("child_process");
const fs = require("fs");

const org = process.argv[process.argv.indexOf("--org") + 1];
const logoPath = process.argv[process.argv.indexOf("--logo") + 1];
if (!org || !logoPath) { console.error("Usage: node upload-brand-assets.js --org <alias> --logo <png>"); process.exit(1); }
const info = JSON.parse(execSync(`sf org display --target-org ${org} --json`, { encoding: "utf8" })).result;
const isProd = info.id.startsWith("00D6g0000081IOg") || !/sandbox/i.test(info.instanceUrl || "");
if (isProd && process.env.CONFIRM_PROD !== "YES") {
  console.error("Refusing to run against production without CONFIRM_PROD=YES");
  process.exit(1);
}
const API = `${info.instanceUrl}/services/data/v62.0`;
const H = { Authorization: `Bearer ${info.accessToken}`, "Content-Type": "application/json" };
const soql = async (q) => (await (await fetch(`${API}/query?q=${encodeURIComponent(q)}`, { headers: H })).json());

(async () => {
  let folder = (await soql(`SELECT Id FROM Folder WHERE DeveloperName = 'Order_Form_Brand_Assets' AND Type = 'Document' LIMIT 1`)).records[0];
  if (!folder) {
    const res = await fetch(`${API}/sobjects/Folder`, { method: "POST", headers: H, body: JSON.stringify({
      Name: "Order Form Brand Assets", DeveloperName: "Order_Form_Brand_Assets", Type: "Document", AccessType: "Public" }) });
    const b = await res.json();
    if (!res.ok) { console.error("Folder create failed:", JSON.stringify(b)); process.exit(1); }
    folder = { Id: b.id };
    console.log("created folder", b.id);
  } else console.log("folder exists", folder.Id);

  const body64 = fs.readFileSync(logoPath).toString("base64");
  let doc = (await soql(`SELECT Id FROM Document ORDER BY CreatedDate DESC LIMIT 200`)).records; // placeholder, replaced below
  doc = (await soql(`SELECT Id FROM Document WHERE DeveloperName = 'Centellic_Logo_2026' LIMIT 1`)).records[0];
  const payload = { Name: "Centellic Logo 2026", DeveloperName: "Centellic_Logo_2026", FolderId: folder.Id,
    Type: "png", ContentType: "image/png", IsPublic: true, Body: body64 };
  if (doc) {
    const res = await fetch(`${API}/sobjects/Document/${doc.Id}`, { method: "PATCH", headers: H, body: JSON.stringify({ Body: body64, IsPublic: true }) });
    console.log("updated document", doc.Id, res.status);
  } else {
    const res = await fetch(`${API}/sobjects/Document`, { method: "POST", headers: H, body: JSON.stringify(payload) });
    const b = await res.json();
    if (!res.ok) { console.error("Document create failed:", JSON.stringify(b)); process.exit(1); }
    doc = { Id: b.id };
    console.log("created document", b.id);
  }
  console.log("LOGO_DOC_ID=" + doc.Id);
  console.log("IMG_URL=/servlet/servlet.ImageServer?id=" + doc.Id + "&oid=" + info.id.slice(0, 15));

  const wmIdx = process.argv.indexOf("--watermark");
  if (wmIdx > -1) {
    const wm64 = fs.readFileSync(process.argv[wmIdx + 1]).toString("base64");
    let wm = (await soql(`SELECT Id FROM Document WHERE DeveloperName = 'Order_Form_Draft_Watermark' LIMIT 1`)).records[0];
    if (wm) {
      const res = await fetch(`${API}/sobjects/Document/${wm.Id}`, { method: "PATCH", headers: H, body: JSON.stringify({ Body: wm64, IsPublic: true }) });
      console.log("updated watermark", wm.Id, res.status);
    } else {
      const res = await fetch(`${API}/sobjects/Document`, { method: "POST", headers: H, body: JSON.stringify({
        Name: "Order Form Draft Watermark", DeveloperName: "Order_Form_Draft_Watermark", FolderId: folder.Id,
        Type: "png", ContentType: "image/png", IsPublic: true, Body: wm64 }) });
      const b = await res.json();
      if (!res.ok) { console.error("Watermark create failed:", JSON.stringify(b)); process.exit(1); }
      wm = { Id: b.id };
      console.log("created watermark", b.id);
    }
    console.log("WATERMARK_DOC_ID=" + wm.Id);
  }
})().catch(e => { console.error(e); process.exit(1); });
