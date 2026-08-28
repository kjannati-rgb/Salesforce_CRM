// node push-template-content.js --org KJDEV
// Idempotent upsert of the Order Form v1.2 CPQ template records, keyed on External_Id__c.
// The single template carries the DRAFT watermark image (SBQQ__WatermarkId__c); whether it
// SHOWS on a given document is the per-quote SBQQ__WatermarkShown__c flag, which the org's
// existing Quote flows set true for Draft/In Review and false on approval.
// Auth via sf CLI session. No npm dependencies (uses global fetch, Node 18+).
const { execSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const org = process.argv[process.argv.indexOf("--org") + 1];
if (!org) { console.error("Usage: node push-template-content.js --org <alias>"); process.exit(1); }

const info = JSON.parse(execSync(`sf org display --target-org ${org} --json`, { encoding: "utf8" })).result;

// Hard production guard (Appendix C)
const isProd = info.id.startsWith("00D6g0000081IOg") || !/sandbox/i.test(info.instanceUrl || "");
if (isProd && process.env.CONFIRM_PROD !== "YES") {
  console.error("Refusing to run against production without CONFIRM_PROD=YES");
  process.exit(1);
}
console.log(`Target: ${info.username} @ ${info.instanceUrl}`);

const API = `${info.instanceUrl}/services/data/v62.0`;
const HEADERS = { Authorization: `Bearer ${info.accessToken}`, "Content-Type": "application/json" };
const DIR = path.join(__dirname, "order-form-v1_2");
const soql = async (q) => (await (await fetch(`${API}/query?q=${encodeURIComponent(q)}`, { headers: HEADERS })).json());

let logoUrl = null; // resolved in main() before contents are pushed
function html(file) {
  // Comments stay in the repo files for developers but must not reach the org:
  // the doc engine fails header/footer content containing <!-- --> with "Bad Request".
  let s = fs.readFileSync(path.join(DIR, file), "utf8").replace(/<!--[\s\S]*?-->/g, "");
  if (s.includes("{{LOGO_URL}}")) {
    if (!logoUrl) { console.error(`${file} needs the Centellic_Logo_2026 Document - run upload-brand-assets.js first`); process.exit(1); }
    s = s.replaceAll("{{LOGO_URL}}", logoUrl);
  }
  return s;
}

async function upsert(type, extId, fields) {
  const url = `${API}/sobjects/${type}/External_Id__c/${encodeURIComponent(extId)}`;
  const res = await fetch(url, { method: "PATCH", headers: HEADERS, body: JSON.stringify(fields) });
  if (res.status === 204) { // updated - fetch Id
    const get = await fetch(url, { headers: HEADERS });
    const rec = await get.json();
    console.log(`  updated ${type} ${extId} -> ${rec.Id}`);
    return rec.Id;
  }
  const body = await res.json();
  if (!res.ok || body.success === false) {
    console.error(`  FAILED ${type} ${extId}:`, JSON.stringify(body));
    process.exit(1);
  }
  console.log(`  created ${type} ${extId} -> ${body.id}`);
  return body.id;
}

(async () => {
  const logoDoc = await soql("SELECT Id FROM Document WHERE DeveloperName = 'Centellic_Logo_2026' LIMIT 1");
  if (logoDoc.records && logoDoc.records.length) {
    logoUrl = `${info.instanceUrl}/servlet/servlet.ImageServer?id=${logoDoc.records[0].Id}&amp;oid=${info.id.slice(0, 15)}`;
    console.log("logo document:", logoDoc.records[0].Id);
  }
  const wmDoc = await soql("SELECT Id FROM Document WHERE DeveloperName = 'Order_Form_Draft_Watermark' LIMIT 1");
  const watermarkId = wmDoc.records && wmDoc.records.length ? wmDoc.records[0].Id : null;
  console.log("watermark document:", watermarkId || "MISSING (run upload-brand-assets.js --watermark)");

  console.log("1/4 Template shell");
  const shell = {
    SBQQ__Default__c: false,
    SBQQ__DeploymentStatus__c: "In Development",
    SBQQ__PageOrientation__c: "Portrait",
    SBQQ__PageHeight__c: 11.69, // A4 - validate in preview, units assumption
    SBQQ__PageWidth__c: 8.27,
    SBQQ__FontFamily__c: "Helvetica", // Aptos/Arial not in CPQ PDF engine - flagged to Legal
    SBQQ__FontSize__c: 9,
    SBQQ__TotalField__c: "Net Total",
    SBQQ__TotalLabel__c: "Total annual fee",
    SBQQ__TotalsHidden__c: false,
    SBQQ__TopMargin__c: 0.75, SBQQ__BottomMargin__c: 0.75,
    SBQQ__LeftMargin__c: 0.75, SBQQ__RightMargin__c: 0.75,
    SBQQ__HeaderHeight__c: 48,
    SBQQ__FooterHeight__c: 34,
    SBQQ__BorderColor__c: "C9D9DD",   // hairline grey-teal
    SBQQ__ShadingColor__c: "EAF3F4",  // brand tint
    SBQQ__PageNumberPosition__c: "Footer",
    SBQQ__PageNumberAlignment__c: "Right",
  };
  const templateId = await upsert("SBQQ__QuoteTemplate__c", "OF-V12-TEMPLATE", {
    ...shell, Name: "Subscription Order Form", SBQQ__WatermarkId__c: watermarkId });
  const templates = [["", templateId]];

  console.log("2/4 Template content");
  const contents = [
    ["OF-V12-CHEAD", "OF v1.2 - Page header", "HTML", "00-page-header.html"],
    ["OF-V12-CFOOT", "OF v1.2 - Page footer", "HTML", "00-page-footer.html"],
    ["OF-V12-C01", "OF v1.2 - 01 Parties", "HTML", "01-parties.html"],
    ["OF-V12-C02", "OF v1.2 - 02 Customer contacts", "HTML", "02-customer-contacts.html"],
    ["OF-V12-C03", "OF v1.2 - 03 Products intro", "HTML", "03-products-intro.html"],
    ["OF-V12-C03B", "OF v1.2 - 03b Tax statement", "HTML", "03b-tax-statement.html"],
    ["OF-V12-C04", "OF v1.2 - 04 Payment terms", "HTML", "04-payment-terms.html"],
    ["OF-V12-C06", "OF v1.2 - 05 Governing law", "HTML", "05-governing-law.html"],
    ["OF-V12-C06B", "OF v1.2 - 06 Special instructions", "HTML", "06-special-instructions.html"],
    ["OF-V12-C07", "OF v1.2 - 07 Special terms", "HTML", "07-special-terms.html"],
    ["OF-V12-C07B", "OF v1.2 - 08 Other terms", "HTML", "07b-other-terms.html"],
    ["OF-V12-C08", "OF v1.2 - 08 Execution", "HTML", "08-execution.html"],
    ["OF-V12-CLINES", "OF v1.2 - Line items", "Line Items", null],
  ];
  const contentIds = {};
  for (const [ext, name, type, file] of contents) {
    const fields = { Name: name, SBQQ__Type__c: type };
    // Engine renders RawMarkup for HTML content; Markup is the sanitized rich-text editor copy.
    if (file) { fields.SBQQ__Markup__c = html(file); fields.SBQQ__RawMarkup__c = html(file); }
    contentIds[ext] = await upsert("SBQQ__TemplateContent__c", ext, fields);
  }

  for (const [suffix, tid] of templates) {
    console.log(`2b/4 Wiring header/footer + removing package-default columns (${suffix || "clean"})`);
    await fetch(`${API}/sobjects/SBQQ__QuoteTemplate__c/${tid}`, { method: "PATCH", headers: HEADERS, body: JSON.stringify({
      SBQQ__HeaderContent__c: contentIds["OF-V12-CHEAD"],
      SBQQ__FooterContent__c: contentIds["OF-V12-CFOOT"],
    }) });
    // The CPQ package auto-creates default line columns (QTY, PART #, ...) on template insert.
    const strays = await soql(`SELECT Id, Name FROM SBQQ__LineColumn__c WHERE SBQQ__Template__c = '${tid}' AND External_Id__c = null`);
    for (const s of strays.records || []) {
      const del = await fetch(`${API}/sobjects/SBQQ__LineColumn__c/${s.Id}`, { method: "DELETE", headers: HEADERS });
      console.log(`  deleted default column "${s.Name}" (${s.Id}) -> ${del.status}`);
    }
  }

  console.log("3/4 Template sections");
  const sections = [
    ["OF-V12-S10", "1 Parties", 10, "OF-V12-C01"],
    ["OF-V12-S20", "2 Customer contacts", 20, "OF-V12-C02"],
    ["OF-V12-S30", "3 Products intro", 30, "OF-V12-C03"],
    ["OF-V12-S40", "3 Products table", 40, "OF-V12-CLINES"],
    ["OF-V12-S50", "3 Tax statement", 50, "OF-V12-C03B"],
    ["OF-V12-S60", "4 Payment", 60, "OF-V12-C04"],
    ["OF-V12-S70", "5 Governing law", 70, "OF-V12-C06"],
    ["OF-V12-S75", "6 Special instructions", 75, "OF-V12-C06B"],
    ["OF-V12-S80", "7 Special terms", 80, "OF-V12-C07"],
    ["OF-V12-S85", "8 Other terms", 85, "OF-V12-C07B"],
    ["OF-V12-S90", "9 Execution", 90, "OF-V12-C08"],
  ];
  for (const [suffix, tid] of templates) {
    for (const [ext, name, order, contentExt] of sections) {
      const fields = {
        Name: name,
        SBQQ__Template__c: tid,
        SBQQ__Content__c: contentIds[contentExt],
        SBQQ__DisplayOrder__c: order,
      };
      if (ext === "OF-V12-S40") fields.SBQQ__QuoteTotalsPrinted__c = true;
      // Execution starts on its own page: the doc engine ignores page-break-inside CSS,
      // so signatures were straddling page breaks (Antheros review 28 Aug).
      if (ext === "OF-V12-S90") fields.SBQQ__PageBreak__c = "Before";
      await upsert("SBQQ__TemplateSection__c", ext + suffix, fields);
    }
  }

  console.log("4/4 Line columns");
  const columns = [
    ["OF-V12-L10", "Product Description", 10, "SBQQ__ProductName__c", 26, "Left"],
    ["OF-V12-L20", "License Model", 20, "License_Model_Display__c", 25, "Left"],
    ["OF-V12-L25", "Qty", 25, "SBQQ__Quantity__c", 5, "Center"],
    ["OF-V12-L30", "Annual fee (excl. tax)", 30, "SBQQ__NetTotal__c", 16, "Right"],
    // Date source switched 2026-08-19 (Kam): real QLE lines leave SBQQ__Start/EndDate__c null
    // and carry term dates in the finance-canonical SUN Report formulas (0.4% null on 180d
    // PROD subs lines vs 100% null raw dates on QLE-built quotes).
    ["OF-V12-L50", "Start date", 50, "Start_Date_SUN_Report__c", 14, "Center"],
    ["OF-V12-L60", "End date", 60, "End_Date_SUN_Report__c", 14, "Center"],
  ];
  // Retired columns (removed from the design) - deleted from the org if present.
  // OF-V12-L40 Currency: dropped 2026-08-18 (Kam) - the fee's automatic ISO prefix already
  // shows the currency, making a separate column redundant.
  const RETIRED_COLUMNS = ["OF-V12-L40"];
  for (const [suffix, tid] of templates) {
    for (const ext of RETIRED_COLUMNS) {
      const gone = await soql(`SELECT Id FROM SBQQ__LineColumn__c WHERE External_Id__c = '${ext}${suffix}'`);
      for (const g of gone.records || []) {
        const del = await fetch(`${API}/sobjects/SBQQ__LineColumn__c/${g.Id}`, { method: "DELETE", headers: HEADERS });
        console.log(`  deleted retired column ${ext}${suffix} -> ${del.status}`);
      }
    }
    for (const [ext, name, order, fieldName, width, align] of columns) {
      await upsert("SBQQ__LineColumn__c", ext + suffix, {
        Name: name,
        SBQQ__Template__c: tid,
        SBQQ__DisplayOrder__c: order,
        SBQQ__FieldName__c: fieldName,
        SBQQ__Width__c: width,
        SBQQ__Alignment__c: align,
      });
    }
  }
  console.log("Push complete.");
})().catch(e => { console.error(e); process.exit(1); });
