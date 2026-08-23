/**
 * REV Order Form v1.2 - writes the signer-typed PO number back to the quote.
 * The Adobe package's form-data engine cannot be used with our custom Quote__c lookup
 * (see runbook 2026-08-20), so this calls the Adobe Acrobat Sign REST API directly:
 *   GET {apiAccessPoint}api/rest/v6/agreements/{documentKey}/formData  -> CSV
 * Auth = integration key from Order_Form_Adobe_Settings__c (entered in the org, never in
 * the repo). Blank key = nothing happens. Writes, all write-when-blank:
 *   PO_Number__c + PO_Required__c (signer question, 2026-08-22)
 *   Customer_VAT_Number_Captured__c + VAT_Registered__c (2026-08-23); the
 *   Quote_Sync_Captured_VAT_to_Account flow relays to Account.Sales_Tax_Number__c only
 *   when the account holds none, with a Sales_Tax_Number_Source__c provenance note.
 */
public with sharing class OrderFormPoWriteback implements Queueable, Database.AllowsCallouts {

    @TestVisible private static final String FORM_FIELD = 'PO_Number';
    @TestVisible private static final String REQUIRED_FIELD = 'PO_Required';
    @TestVisible private static final String VAT_FIELD = 'VAT_Number';
    @TestVisible private static final String VAT_REGISTERED_FIELD = 'VAT_Registered';
    private final Id agreementId;

    public OrderFormPoWriteback(Id agreementId) {
        this.agreementId = agreementId;
    }

    public static Boolean isConfigured() {
        Order_Form_Adobe_Settings__c s = Order_Form_Adobe_Settings__c.getOrgDefaults();
        return s != null && String.isNotBlank(s.Integration_Key__c);
    }

    public void execute(QueueableContext ctx) {
        if (!isConfigured()) {
            return;
        }
        List<echosign_dev1__SIGN_Agreement__c> ags = [
            SELECT Id, Quote__c, echosign_dev1__Document_Key__c, Quote__r.Name,
                   Quote__r.PO_Number__c, Quote__r.PO_Required__c,
                   Quote__r.Customer_VAT_Number_Captured__c, Quote__r.VAT_Registered__c,
                   Quote__r.SBQQ__Account__c, Quote__r.SBQQ__Account__r.Sales_Tax_Number__c
            FROM echosign_dev1__SIGN_Agreement__c
            WHERE Id = :agreementId AND Quote__c != null
            LIMIT 1
        ];
        if (ags.isEmpty() || String.isBlank(ags[0].echosign_dev1__Document_Key__c)) {
            return;
        }
        echosign_dev1__SIGN_Agreement__c ag = ags[0];
        Map<String, String> form = fetchFormRow(ag.echosign_dev1__Document_Key__c);
        if (form == null) {
            return;
        }
        SBQQ__Quote__c q = new SBQQ__Quote__c(Id = ag.Quote__c);
        Boolean changed = false;
        // rep-entered PO stands; the signer field only existed when it was blank
        String po = form.get(FORM_FIELD.toLowerCase());
        if (String.isBlank(ag.Quote__r.PO_Number__c) && String.isNotBlank(po)) {
            q.PO_Number__c = po.left(255);
            changed = true;
        }
        // the signer's Yes/No answer to "Does your organisation require a PO number on invoices?"
        String required = form.get(REQUIRED_FIELD.toLowerCase());
        if (String.isBlank(ag.Quote__r.PO_Required__c) && (required == 'Yes' || required == 'No')) {
            q.PO_Required__c = required;
            changed = true;
        }
        // VAT / GST / sales tax (Kam 2026-08-23): the signer's registered Yes/No and the number.
        String vatRegistered = form.get(VAT_REGISTERED_FIELD.toLowerCase());
        if (String.isBlank(ag.Quote__r.VAT_Registered__c) && (vatRegistered == 'Yes' || vatRegistered == 'No')) {
            q.VAT_Registered__c = vatRegistered;
            changed = true;
        }
        String vat = form.get(VAT_FIELD.toLowerCase());
        if (String.isBlank(ag.Quote__r.Customer_VAT_Number_Captured__c) && String.isNotBlank(vat)) {
            q.Customer_VAT_Number_Captured__c = vat.left(255);
            changed = true;
        }
        // The Account (permanent home of the number) is written by the
        // Quote_Sync_Captured_VAT_to_Account flow ONLY when it holds none, with a provenance note.
        if (changed) {
            update q;
        }
    }

    /** Fetches the agreement's form-data CSV and returns the first data row keyed by lower-cased header. */
    @TestVisible
    private static Map<String, String> fetchFormRow(String documentKey) {
        Order_Form_Adobe_Settings__c s = Order_Form_Adobe_Settings__c.getOrgDefaults();
        String base = String.isNotBlank(s.API_Base_URI__c) ? s.API_Base_URI__c : discoverBaseUri(s.Integration_Key__c);
        if (String.isBlank(base)) {
            return null;
        }
        if (!base.endsWith('/')) {
            base += '/';
        }
        HttpRequest req = new HttpRequest();
        req.setEndpoint(base + 'api/rest/v6/agreements/' + EncodingUtil.urlEncode(documentKey, 'UTF-8') + '/formData');
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + s.Integration_Key__c);
        req.setTimeout(60000);
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            return null;
        }
        return csvRow(res.getBody());
    }

    private static String discoverBaseUri(String key) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.echosign.com/api/rest/v6/baseUris');
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + key);
        req.setTimeout(30000);
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            return null;
        }
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        return (String) body.get('apiAccessPoint');
    }

    /** Minimal CSV reader: header row + first data row (quoted fields with commas supported), keyed by lower-cased header. */
    @TestVisible
    private static Map<String, String> csvRow(String csv) {
        if (String.isBlank(csv)) {
            return null;
        }
        // Adobe prefixes the CSV with a UTF-8 byte-order mark (seen live 2026-08-21)
        String bom = String.fromCharArray(new List<Integer>{ 65279 });
        if (csv.startsWith(bom)) {
            csv = csv.substring(1);
        }
        List<String> lines = csv.replace('\r\n', '\n').replace('\r', '\n').split('\n');
        if (lines.size() < 2) {
            return null;
        }
        List<String> headers = splitCsvLine(lines[0]);
        List<String> values = splitCsvLine(lines[1]);
        Map<String, String> row = new Map<String, String>();
        for (Integer i = 0; i < headers.size() && i < values.size(); i++) {
            String v = values[i].trim();
            row.put(headers[i].trim().toLowerCase(), String.isBlank(v) ? null : v);
        }
        return row;
    }

    @TestVisible
    private static String csvField(String csv, String fieldName) {
        Map<String, String> row = csvRow(csv);
        return row == null ? null : row.get(fieldName.toLowerCase());
    }

    private static List<String> splitCsvLine(String line) {
        List<String> out = new List<String>();
        String cur = '';
        Boolean inQuotes = false;
        Integer i = 0;
        while (i < line.length()) {
            String ch = line.substring(i, i + 1);
            if (ch == '"') {
                if (inQuotes && i + 1 < line.length() && line.substring(i + 1, i + 2) == '"') {
                    cur += '"';
                    i++;
                } else {
                    inQuotes = !inQuotes;
                }
            } else if (ch == ',' && !inQuotes) {
                out.add(cur);
                cur = '';
            } else {
                cur += ch;
            }
            i++;
        }
        out.add(cur);
        return out;
    }
}
