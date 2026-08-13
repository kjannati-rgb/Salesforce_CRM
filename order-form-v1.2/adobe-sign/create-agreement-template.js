// node create-agreement-template.js --org KJDEV
// Creates the Order Form v1.2 Adobe Sign agreement template, merge mapping, and data
// mapping as data records in the echosign_dev1 namespace. Idempotent: identifies each
// record by a WHERE clause and updates in place. Re-run in production during Phase 6
// (CONFIRM_PROD=YES) instead of re-keying by hand.
//
// Record model (validated against package v24.35 describes + PROD conventions):
// - Form_Field_Mapping, Form_Field_Mapping_Entry, File_Mapping, Recipient_Template and
//   Attachment_Template have AUTO-NUMBER Name fields (PROD's "0000001" names) - never set Name.
// - SIGN_Field_Mapping__c.Name is writable and holds the TARGET field API name.
// - SIGN_Object_Mapping__c.Field_API_Name__c = lookup on the Agreement that reaches the
//   target record (custom Quote__c added for this project); Fully_Qualified_API__c = target object.
// - Merge-mapping entries with blank Object_Reference_Path__c read from the master object.
const { execSync } = require("child_process");

const org = process.argv[process.argv.indexOf("--org") + 1];
if (!org) { console.error("Usage: node create-agreement-template.js --org <alias>"); process.exit(1); }
const info = JSON.parse(execSync(`sf org display --target-org ${org} --json`, { encoding: "utf8" })).result;
const isProd = info.id.startsWith("00D6g0000081IOg") || !/sandbox/i.test(info.instanceUrl || "");
if (isProd && process.env.CONFIRM_PROD !== "YES") {
  console.error("Refusing to run against production without CONFIRM_PROD=YES");
  process.exit(1);
}
console.log(`Target: ${info.username} @ ${info.instanceUrl}`);
const API = `${info.instanceUrl}/services/data/v62.0`;
const H = { Authorization: `Bearer ${info.accessToken}`, "Content-Type": "application/json" };
const soql = async (q) => (await (await fetch(`${API}/query?q=${encodeURIComponent(q)}`, { headers: H })).json());

// label: display only. where: WHERE clause identifying the record for idempotent re-runs.
// setName: false for objects with auto-number Name.
async function upsertWhere(type, label, where, fields, setName = true) {
  const existing = await soql(`SELECT Id FROM ${type} WHERE ${where} LIMIT 1`);
  if (existing.records && existing.records.length) {
    const id = existing.records[0].Id;
    const res = await fetch(`${API}/sobjects/${type}/${id}`, { method: "PATCH", headers: H, body: JSON.stringify(fields) });
    if (res.status !== 204) { console.error(`FAILED update ${type} ${label}:`, await res.text()); process.exit(1); }
    console.log(`  updated ${type} "${label}" -> ${id}`);
    return id;
  }
  const payload = setName ? { Name: label, ...fields } : fields;
  const res = await fetch(`${API}/sobjects/${type}`, { method: "POST", headers: H, body: JSON.stringify(payload) });
  const body = await res.json();
  if (!res.ok) { console.error(`FAILED create ${type} ${label}:`, JSON.stringify(body)); process.exit(1); }
  console.log(`  created ${type} "${label}" -> ${body.id}`);
  return body.id;
}

(async () => {
  console.log("1/3 Merge mapping (Salesforce -> signer form fields)");
  const mergeId = await upsertWhere("echosign_dev1__SIGN_Merge_Mapping__c",
    "Order Form v1.2 - Merge Mapping", "Name = 'Order Form v1.2 - Merge Mapping'", {
    echosign_dev1__Description__c: "Pre-fills VAT_Number and PO_Number signer fields from the master Quote when values are already held.",
  });
  const ffmVat = await upsertWhere("echosign_dev1__SIGN_Form_Field_Mapping__c", "VAT_Number",
    `echosign_dev1__Data_Mapping__c = '${mergeId}' AND echosign_dev1__Form_Field_Name__c = 'VAT_Number'`,
    { echosign_dev1__Data_Mapping__c: mergeId, echosign_dev1__Form_Field_Name__c: "VAT_Number", echosign_dev1__Input_Type__c: "Text", echosign_dev1__Index__c: 1 }, false);
  await upsertWhere("echosign_dev1__SIGN_Form_Field_Mapping_Entry__c", "VAT from Quote",
    `echosign_dev1__Form_Field_Mapping__c = '${ffmVat}'`,
    { echosign_dev1__Form_Field_Mapping__c: ffmVat, echosign_dev1__Type__c: "Salesforce Object Field", echosign_dev1__Field_Reference_Name__c: "Customer_VAT_Number__c", echosign_dev1__Index__c: 1 }, false);
  const ffmPo = await upsertWhere("echosign_dev1__SIGN_Form_Field_Mapping__c", "PO_Number",
    `echosign_dev1__Data_Mapping__c = '${mergeId}' AND echosign_dev1__Form_Field_Name__c = 'PO_Number'`,
    { echosign_dev1__Data_Mapping__c: mergeId, echosign_dev1__Form_Field_Name__c: "PO_Number", echosign_dev1__Input_Type__c: "Text", echosign_dev1__Index__c: 2 }, false);
  await upsertWhere("echosign_dev1__SIGN_Form_Field_Mapping_Entry__c", "PO from Quote",
    `echosign_dev1__Form_Field_Mapping__c = '${ffmPo}'`,
    { echosign_dev1__Form_Field_Mapping__c: ffmPo, echosign_dev1__Type__c: "Salesforce Object Field", echosign_dev1__Field_Reference_Name__c: "PO_Number__c", echosign_dev1__Index__c: 1 }, false);

  console.log("2/3 Data mapping (signed values -> Salesforce)");
  const dataId = await upsertWhere("echosign_dev1__SIGN_Data_Mapping__c",
    "Order Form v1.2 - Write-back", "Name = 'Order Form v1.2 - Write-back'", {
    echosign_dev1__Description__c: "On Signed: PO/VAT signer fields and signed date to the Quote (VAT relays to Account via Quote_Sync_Captured_VAT_to_Account flow); signed PDF filed on the Quote.",
  });
  const omQuote = await upsertWhere("echosign_dev1__SIGN_Object_Mapping__c", "Quote",
    `echosign_dev1__SIGN_Data_Mapping__c = '${dataId}' AND Name = 'Quote'`,
    { echosign_dev1__SIGN_Data_Mapping__c: dataId, echosign_dev1__Display_Label__c: "Quote", echosign_dev1__Field_API_Name__c: "Quote__c", echosign_dev1__Fully_Qualified_API__c: "SBQQ__Quote__c" });
  await upsertWhere("echosign_dev1__SIGN_Field_Mapping__c", "PO_Number__c",
    `echosign_dev1__SIGN_Object_Mapping__c = '${omQuote}' AND Name = 'PO_Number__c'`,
    { echosign_dev1__SIGN_Object_Mapping__c: omQuote, echosign_dev1__Type__c: "EchoSign Form Field", echosign_dev1__Source__c: "PO_Number", echosign_dev1__Do_Not_Write_Empty__c: true, echosign_dev1__Index__c: 1, echosign_dev1__Map_on_Events__c: "Signed" });
  await upsertWhere("echosign_dev1__SIGN_Field_Mapping__c", "Customer_VAT_Number_Captured__c",
    `echosign_dev1__SIGN_Object_Mapping__c = '${omQuote}' AND Name = 'Customer_VAT_Number_Captured__c'`,
    { echosign_dev1__SIGN_Object_Mapping__c: omQuote, echosign_dev1__Type__c: "EchoSign Form Field", echosign_dev1__Source__c: "VAT_Number", echosign_dev1__Do_Not_Write_Empty__c: true, echosign_dev1__Index__c: 2, echosign_dev1__Map_on_Events__c: "Signed" });
  await upsertWhere("echosign_dev1__SIGN_Field_Mapping__c", "Customer_Signed_Date__c",
    `echosign_dev1__SIGN_Object_Mapping__c = '${omQuote}' AND Name = 'Customer_Signed_Date__c'`,
    { echosign_dev1__SIGN_Object_Mapping__c: omQuote, echosign_dev1__Type__c: "Agreement Field", echosign_dev1__Source__c: "echosign_dev1__DateSignedDate__c", echosign_dev1__Do_Not_Write_Empty__c: true, echosign_dev1__Index__c: 3, echosign_dev1__Map_on_Events__c: "Signed" });
  await upsertWhere("echosign_dev1__SIGN_File_Mapping__c", "Signed PDF to Quote",
    `echosign_dev1__SIGN_Object_Mapping__c = '${omQuote}'`,
    { echosign_dev1__SIGN_Object_Mapping__c: omQuote, echosign_dev1__Source_Type__c: "Signed Agreement - Merged PDF", echosign_dev1__Target_Type__c: "Attach file directly to object", echosign_dev1__Target_Document_Type__c: "Files", echosign_dev1__Index__c: 1, echosign_dev1__Map_on_Events__c: "Signed" }, false);

  console.log("3/3 Agreement template");
  const tmplId = await upsertWhere("echosign_dev1__Agreement_Template__c",
    "Order Form v1.2 - Subscription", "Name = 'Order Form v1.2 - Subscription'", {
    echosign_dev1__Name__c: "Order Form - {!SBQQ__BillingName__c} - {!Name}",
    echosign_dev1__Master_Object_Type__c: "SBQQ__Quote__c",
    echosign_dev1__Active__c: true,
    echosign_dev1__Default__c: false,
    echosign_dev1__Auto_Send__c: true,
    echosign_dev1__Signature_Type__c: "e-Signature",
    echosign_dev1__Signature_Flow__c: "Recipients sign in order",
    echosign_dev1__Language__c: "English (United Kingdom)",
    echosign_dev1__Merge_Mapping__c: mergeId,
    echosign_dev1__Data_Mapping__c: dataId,
    echosign_dev1__Message__c: "Please review and sign the attached Order Form.",
  });
  await upsertWhere("echosign_dev1__Recipient_Template__c", "signer 1",
    `echosign_dev1__Agreement_Template__c = '${tmplId}' AND echosign_dev1__Index__c = 1`,
    { echosign_dev1__Agreement_Template__c: tmplId, echosign_dev1__Type__c: "Look Up Based on Master Object Field", echosign_dev1__Recipient_Type__c: "Contact", echosign_dev1__Recipient_Role__c: "Signer", echosign_dev1__Recipient_Field__c: "Signatory_Contact__c", echosign_dev1__Index__c: 1 }, false);
  await upsertWhere("echosign_dev1__Attachment_Template__c", "quote document",
    `echosign_dev1__Agreement_Template__c = '${tmplId}' AND echosign_dev1__Index__c = 0`,
    { echosign_dev1__Agreement_Template__c: tmplId, echosign_dev1__Type__c: "Quote Document from Master Quote", echosign_dev1__Quote_Document_Selection_Type__c: "Latest Document", echosign_dev1__Quote_Document_Selection_Field__c: "Last Modified Date", echosign_dev1__Index__c: 0 }, false);
  console.log("Done. Template Id:", tmplId);
})().catch(e => { console.error(e); process.exit(1); });
