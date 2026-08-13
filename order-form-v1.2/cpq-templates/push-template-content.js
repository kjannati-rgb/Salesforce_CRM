// node push-template-content.js --org KJDEV
// Idempotent upsert of the Order Form v1.2 CPQ template records, keyed on External_Id__c.
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

function html(file) {
  return fs.readFileSync(path.join(DIR, file), "utf8");
}

(async () => {
  console.log("1/4 Template shell");
  const templateId = await upsert("SBQQ__QuoteTemplate__c", "OF-V12-TEMPLATE", {
    Name: "Order Form v1.2 - Subscriptions",
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
  });

  console.log("2/4 Template content");
  const contents = [
    ["OF-V12-C01", "OF v1.2 - 01 Parties", "HTML", "01-parties.html"],
    ["OF-V12-C02", "OF v1.2 - 02 Customer contacts", "HTML", "02-customer-contacts.html"],
    ["OF-V12-C03", "OF v1.2 - 03 Products intro", "HTML", "03-products-intro.html"],
    ["OF-V12-C03B", "OF v1.2 - 03b Tax statement", "HTML", "03b-tax-statement.html"],
    ["OF-V12-C04", "OF v1.2 - 04 Payment terms", "HTML", "04-payment-terms.html"],
    ["OF-V12-C06", "OF v1.2 - 06 Governing law", "HTML", "06-governing-law.html"],
    ["OF-V12-C07", "OF v1.2 - 07 Special terms", "HTML", "07-special-terms.html"],
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

  // The CPQ package auto-creates default line columns (QTY, PART #, ...) on template insert.
  // Remove anything on this template that our push does not own (no External_Id__c).
  console.log("2b/4 Removing package-default line columns");
  const strays = await (await fetch(`${API}/query?q=${encodeURIComponent(
    `SELECT Id, Name FROM SBQQ__LineColumn__c WHERE SBQQ__Template__c = '${templateId}' AND External_Id__c = null`)}`,
    { headers: HEADERS })).json();
  for (const s of strays.records || []) {
    const del = await fetch(`${API}/sobjects/SBQQ__LineColumn__c/${s.Id}`, { method: "DELETE", headers: HEADERS });
    console.log(`  deleted default column "${s.Name}" (${s.Id}) -> ${del.status}`);
  }

  console.log("3/4 Template sections");
  const sections = [
    ["OF-V12-S10", "1 Parties", 10, "OF-V12-C01"],
    ["OF-V12-S20", "2 Customer contacts", 20, "OF-V12-C02"],
    ["OF-V12-S30", "3 Products intro", 30, "OF-V12-C03"],
    ["OF-V12-S40", "3 Products table", 40, "OF-V12-CLINES"],
    ["OF-V12-S50", "3 Tax statement", 50, "OF-V12-C03B"],
    ["OF-V12-S60", "4 Payment", 60, "OF-V12-C04"],
    ["OF-V12-S70", "6 Governing law", 70, "OF-V12-C06"],
    ["OF-V12-S80", "7 Special terms", 80, "OF-V12-C07"],
    ["OF-V12-S90", "8 Execution", 90, "OF-V12-C08"],
  ];
  for (const [ext, name, order, contentExt] of sections) {
    const fields = {
      Name: name,
      SBQQ__Template__c: templateId,
      SBQQ__Content__c: contentIds[contentExt],
      SBQQ__DisplayOrder__c: order,
    };
    if (ext === "OF-V12-S40") fields.SBQQ__QuoteTotalsPrinted__c = true;
    await upsert("SBQQ__TemplateSection__c", ext, fields);
  }

  console.log("4/4 Line columns");
  const columns = [
    ["OF-V12-L10", "Product Description", 10, "SBQQ__ProductName__c", 26, "Left"],
    ["OF-V12-L20", "License Model", 20, "License_Model_Display__c", 26, "Left"],
    ["OF-V12-L30", "Annual fee (excl. tax)", 30, "SBQQ__NetTotal__c", 16, "Right"],
    ["OF-V12-L40", "Currency", 40, "CurrencyIsoCode", 8, "Center"],
    ["OF-V12-L50", "Start date", 50, "SBQQ__StartDate__c", 12, "Center"],
    ["OF-V12-L60", "End date", 60, "SBQQ__EndDate__c", 12, "Center"],
  ];
  for (const [ext, name, order, fieldName, width, align] of columns) {
    await upsert("SBQQ__LineColumn__c", ext, {
      Name: name,
      SBQQ__Template__c: templateId,
      SBQQ__DisplayOrder__c: order,
      SBQQ__FieldName__c: fieldName,
      SBQQ__Width__c: width,
      SBQQ__Alignment__c: align,
    });
  }
  console.log("Push complete.");
})().catch(e => { console.error(e); process.exit(1); });
