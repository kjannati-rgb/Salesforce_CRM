// node push-contributor-template.js --org KJDEV
// Contributor Order Form (16 Sep 2026). Same shell as the Subscription Order Form; shared HTML is read from
// order-form-v1_2/ and the contributor-specific files from order-form-contributor/. Shared CPQ contents
// (OF-V12-*) are looked up, never re-pushed; contributor contents are OF-C1-*.
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
const CDIR = path.join(__dirname, "order-form-contributor");
const soql = async (q) => (await (await fetch(`${API}/query?q=${encodeURIComponent(q)}`, { headers: HEADERS })).json());

let logoUrl = null; // resolved in main() before contents are pushed
function html(file) {
  // Comments stay in the repo files for developers but must not reach the org:
  // the doc engine fails header/footer content containing <!-- --> with "Bad Request".
  const p = fs.existsSync(path.join(CDIR, file)) ? path.join(CDIR, file) : path.join(DIR, file);
  let s = fs.readFileSync(p, "utf8").replace(/<!--[\s\S]*?-->/g, "");
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
    SBQQ__TotalLabel__c: "Total fee",
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
  const templateId = await upsert("SBQQ__QuoteTemplate__c", "OF-C1-TEMPLATE", {
    ...shell, Name: "Contributor Order Form", SBQQ__WatermarkId__c: watermarkId });
  const templates = [["", templateId]];

  console.log("2/4 Template content");
  const contents = [
    ["OF-C1-C01", "OF Contributor - 01 Parties", "HTML", "01-parties.html"],
    ["OF-C1-C03", "OF Contributor - 03 Contributions intro", "HTML", "03-contributions-intro.html"],
    ["OF-C1-C04", "OF Contributor - 04 Payment terms", "HTML", "04-payment-terms.html"],
    ["OF-C1-CLINES", "OF Contributor - Line items", "Line Items", null],
    ["OF-C1-CLINESD", "OF Contributor - Line items (with discount)", "Line Items", null],
    ["OF-C1-CLICENCE", "OF Contributor - Licence terms lines", "Line Items", null],
  ];
  // Shared with the Subscription Order Form - looked up by External Id, never re-pushed from here.
  const SHARED = ["OF-V12-CHEAD", "OF-V12-CFOOT", "OF-V12-C02", "OF-V12-C03B", "OF-V12-C03L", "OF-V12-C06", "OF-V12-C06B", "OF-V12-C07", "OF-V12-C07B", "OF-V12-C08"];
  const contentIds = {};
  for (const ext of SHARED) {
    const found = await soql(`SELECT Id FROM SBQQ__TemplateContent__c WHERE External_Id__c = '${ext}'`);
    if (!found.records || !found.records.length) { console.error(`shared content ${ext} missing - push the Subscription Order Form first`); process.exit(1); }
    contentIds[ext] = found.records[0].Id;
  }
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
      // The Generate Document picker only lists Deployed templates - "In Development"
      // makes the template invisible to reps (caught on camera 28 Aug).
      SBQQ__DeploymentStatus__c: "Deployed",
    }) });
    // The CPQ package auto-creates default line columns (QTY, PART #, ...) on template insert.
    const strays = await soql(`SELECT Id, Name FROM SBQQ__LineColumn__c WHERE SBQQ__Template__c = '${tid}' AND External_Id__c = null`);
    for (const s of strays.records || []) {
      const del = await fetch(`${API}/sobjects/SBQQ__LineColumn__c/${s.Id}`, { method: "DELETE", headers: HEADERS });
      console.log(`  deleted default column "${s.Name}" (${s.Id}) -> ${del.status}`);
    }
  }

  console.log("3/4 Template sections");
  const sectionIds = {};
  const sections = [
    ["OF-C1-S10", "1 Parties", 10, "OF-C1-C01"],
    ["OF-C1-S20", "2 Customer contacts", 20, "OF-V12-C02"],
    ["OF-C1-S30", "3 Contributions intro", 30, "OF-C1-C03"],
    // Two products tables, one prints: net-only by default, list price + discount when the rep ticks Show discount.
    ["OF-C1-S40", "3 Contributions table", 40, "OF-C1-CLINES", { printIf: "Order_Form_Not_Show_Discount__c" }],
    ["OF-C1-S41", "3 Contributions table (discount)", 41, "OF-C1-CLINESD", { printIf: "Order_Form_Show_Discount__c" }],
    // Licence block only when a subscription line is cross-sold on the same quote.
    ["OF-C1-S44", "3b Licence terms intro", 44, "OF-V12-C03L", { printIf: "Order_Form_Has_Subs__c" }],
    ["OF-C1-S45", "3b Licence terms table", 45, "OF-C1-CLICENCE", { printIf: "Order_Form_Has_Subs__c" }],
    ["OF-C1-S50", "3 Tax statement", 50, "OF-V12-C03B"],
    ["OF-C1-S60", "4 Payment", 60, "OF-C1-C04"],
    ["OF-C1-S70", "5 Governing law", 70, "OF-V12-C06"],
    ["OF-C1-S75", "6 Special instructions", 75, "OF-V12-C06B"],
    ["OF-C1-S80", "7 Special terms", 80, "OF-V12-C07"],
    ["OF-C1-S85", "8 Other terms", 85, "OF-V12-C07B"],
    ["OF-C1-S90", "9 Execution", 90, "OF-V12-C08"],
  ];
  // Retired sections/contents (removed from the design) - deleted from the org if present. Sections first
  // (they reference contents). 14 Sep 2026: a Legal Monitor variant of the terms sentence + a Schedule 1
  // printing the legacy Legal Monitor T&Cs was built and then withdrawn the same day - the GC ruled Legal
  // Monitor sits under the General Subscription Terms like every other subs product.
  const RETIRED_SECTIONS = [];
  const RETIRED_CONTENTS = [];
  for (const [suffix] of templates) {
    for (const ext of RETIRED_SECTIONS) {
      const gone = await soql(`SELECT Id FROM SBQQ__TemplateSection__c WHERE External_Id__c = '${ext}${suffix}'`);
      for (const g of gone.records || []) {
        const del = await fetch(`${API}/sobjects/SBQQ__TemplateSection__c/${g.Id}`, { method: "DELETE", headers: HEADERS });
        console.log(`  deleted retired section ${ext}${suffix} -> ${del.status}`);
      }
    }
  }
  for (const ext of RETIRED_CONTENTS) {
    const gone = await soql(`SELECT Id FROM SBQQ__TemplateContent__c WHERE External_Id__c = '${ext}'`);
    for (const g of gone.records || []) {
      const del = await fetch(`${API}/sobjects/SBQQ__TemplateContent__c/${g.Id}`, { method: "DELETE", headers: HEADERS });
      console.log(`  deleted retired content ${ext} -> ${del.status}`);
    }
  }
  for (const [suffix, tid] of templates) {
    for (const [ext, name, order, contentExt, opts] of sections) {
      if (!contentIds[contentExt]) { console.log(`  skipped section ${ext} (no content)`); continue; }
      const fields = {
        Name: name,
        SBQQ__Template__c: tid,
        SBQQ__Content__c: contentIds[contentExt],
        SBQQ__DisplayOrder__c: order,
        SBQQ__FilterField__c: null, SBQQ__FilterOperator__c: null, SBQQ__FilterValue__c: null, SBQQ__PageBreak__c: null,
        SBQQ__ConditionalPrintField__c: null,
      };
      // Conditional sections (HTML / quote-terms content): CPQ prints the section only when the named
      // quote CHECKBOX is true (Conditional Print Field). Filter Field/Operator/Value only filter LINE rows -
      // they do not suppress an HTML section (14 Sep 2026: both terms sentences printed until this was switched).
      if (opts && opts.printIf) fields.SBQQ__ConditionalPrintField__c = opts.printIf;
      if (opts && opts.pageBreak) fields.SBQQ__PageBreak__c = opts.pageBreak;
      // Products table: all lines except hidden Legal Monitor bundle parents (14 Sep 2026); quote totals row on.
      if (ext === "OF-C1-S40" || ext === "OF-C1-S41") {
        fields.SBQQ__QuoteTotalsPrinted__c = true;
        fields.SBQQ__FilterField__c = "Order_Form_Print_Contrib_Row__c";
        fields.SBQQ__FilterOperator__c = "equals";
        fields.SBQQ__FilterValue__c = "true";
      }
      // Licence terms table: one row per product (first MDQ segment only, no hidden bundle parents), no totals row.
      if (ext === "OF-C1-S45") {
        fields.SBQQ__FilterField__c = "Order_Form_Print_Licence_Row__c";
        fields.SBQQ__FilterOperator__c = "equals";
        fields.SBQQ__FilterValue__c = "true";
        fields.SBQQ__SummaryDisplay__c = "Never";
      }
      // Execution starts on its own page: the doc engine ignores page-break-inside CSS,
      // so signatures were straddling page breaks (Antheros review 28 Aug).
      if (ext === "OF-C1-S90") fields.SBQQ__PageBreak__c = "Before";
      sectionIds[ext + suffix] = await upsert("SBQQ__TemplateSection__c", ext + suffix, fields);
    }
  }

  console.log("4/4 Line columns");
  // Every column is pinned to its section: columns without a Section print in EVERY
  // Line Items section, which would drag the fee/date columns into the licence block.
  const columns = [
    ["OF-C1-L10", "Publication and product", 10, "SBQQ__ProductName__c", 28, "Left", "OF-C1-S40"],
    ["OF-C1-L20", "Content", 20, "Order_Form_Content__c", 36, "Left", "OF-C1-S40"],
    ["OF-C1-L50", "Date", 50, "Order_Form_Line_Date__c", 11, "Center", "OF-C1-S40"],
    ["OF-C1-L60", "End date", 60, "Order_Form_Line_End_Date__c", 11, "Center", "OF-C1-S40"],
    ["OF-C1-L30", "Fee (excl. tax)", 70, "SBQQ__NetTotal__c", 14, "Right", "OF-C1-S40"],
    ["OF-C1-LD10", "Publication and product", 10, "SBQQ__ProductName__c", 20, "Left", "OF-C1-S41"],
    ["OF-C1-LD20", "Content", 20, "Order_Form_Content__c", 22, "Left", "OF-C1-S41"],
    ["OF-C1-LD50", "Date", 50, "Order_Form_Line_Date__c", 12, "Center", "OF-C1-S41"],
    ["OF-C1-LD60", "End date", 60, "Order_Form_Line_End_Date__c", 12, "Center", "OF-C1-S41"],
    ["OF-C1-LD25", "List price", 65, "SBQQ__ListPrice__c", 10, "Right", "OF-C1-S41"],
    ["OF-C1-LD27", "Discount", 67, "SBQQ__AdditionalDiscount__c", 10, "Right", "OF-C1-S41"],
    ["OF-C1-LD30", "Fee (excl. tax)", 70, "SBQQ__NetTotal__c", 12, "Right", "OF-C1-S41"],
    ["OF-C1-LT10", "Product", 10, "SBQQ__ProductName__c", 30, "Left", "OF-C1-S45"],
    ["OF-C1-LT20", "Terms", 20, "License_Model_Display__c", 70, "Left", "OF-C1-S45"],
  ];
  // Retired columns (removed from the design) - deleted from the org if present.
  // OF-V12-L40 Currency: dropped 2026-08-18 (Kam) - the fee's automatic ISO prefix already
  // shows the currency, making a separate column redundant.
  // OF-V12-L25 Qty: dropped 2026-09-01 (Kam) - seat counts already print in contract language
  // in the License Model column, the fee is a line total with no unit price to multiply, and
  // most forms showed a column of "1.00"s. Width redistributed to Product/License Model.
  // OF-V12-L20 License Model: dropped 2026-09-13 (Kam, on Richard Green's feedback) - the wording
  // now prints once per product in the Licence terms block; width went to Product/fee/dates.
  const RETIRED_COLUMNS = [];
  for (const [suffix, tid] of templates) {
    for (const ext of RETIRED_COLUMNS) {
      const gone = await soql(`SELECT Id FROM SBQQ__LineColumn__c WHERE External_Id__c = '${ext}${suffix}'`);
      for (const g of gone.records || []) {
        const del = await fetch(`${API}/sobjects/SBQQ__LineColumn__c/${g.Id}`, { method: "DELETE", headers: HEADERS });
        console.log(`  deleted retired column ${ext}${suffix} -> ${del.status}`);
      }
    }
    for (const [ext, name, order, fieldName, width, align, sectionExt] of columns) {
      await upsert("SBQQ__LineColumn__c", ext + suffix, {
        Name: name,
        SBQQ__Template__c: tid,
        SBQQ__Section__c: sectionIds[sectionExt + suffix],
        SBQQ__DisplayOrder__c: order,
        SBQQ__FieldName__c: fieldName,
        SBQQ__Width__c: width,
        SBQQ__Alignment__c: align,
      });
    }
  }
  console.log("Push complete.");
})().catch(e => { console.error(e); process.exit(1); });
