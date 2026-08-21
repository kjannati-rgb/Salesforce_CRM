/**
 * REV Order Form v1.2 - writes the signer-typed PO number back to the quote.
 * The Adobe package's form-data engine cannot be used with our custom Quote__c lookup
 * (see runbook 2026-08-20), so this calls the Adobe Acrobat Sign REST API directly:
 *   GET {apiAccessPoint}api/rest/v6/agreements/{documentKey}/formData  -> CSV
 * Auth = integration key from Order_Form_Adobe_Settings__c (entered in the org, never in
 * the repo). Blank key = nothing happens. Only PO is written (Kam 2026-08-21: VAT not for
 * now); write-when-blank so a PO already on the quote is never overwritten.
 */
public with sharing class OrderFormPoWriteback implements Queueable, Database.AllowsCallouts {

    @TestVisible private static final String FORM_FIELD = 'PO_Number';
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
            SELECT Id, Quote__c, echosign_dev1__Document_Key__c, Quote__r.PO_Number__c
            FROM echosign_dev1__SIGN_Agreement__c
            WHERE Id = :agreementId AND Quote__c != null
            LIMIT 1
        ];
        if (ags.isEmpty() || String.isBlank(ags[0].echosign_dev1__Document_Key__c)) {
            return;
        }
        echosign_dev1__SIGN_Agreement__c ag = ags[0];
        if (String.isNotBlank(ag.Quote__r.PO_Number__c)) {
            return; // rep-entered PO stands; the signer field only existed when it was blank
        }
        String po = fetchFormField(ag.echosign_dev1__Document_Key__c, FORM_FIELD);
        if (String.isNotBlank(po)) {
            update new SBQQ__Quote__c(Id = ag.Quote__c, PO_Number__c = po.left(255));
        }
    }

    /** Returns the value of one form field from the agreement's form-data CSV, or null. */
    @TestVisible
    private static String fetchFormField(String documentKey, String fieldName) {
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
        return csvField(res.getBody(), fieldName);
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

    /** Minimal CSV reader: header row + first data row, quoted fields with commas supported. */
    @TestVisible
    private static String csvField(String csv, String fieldName) {
        if (String.isBlank(csv)) {
            return null;
        }
        List<String> lines = csv.replace('\r\n', '\n').replace('\r', '\n').split('\n');
        if (lines.size() < 2) {
            return null;
        }
        List<String> headers = splitCsvLine(lines[0]);
        List<String> values = splitCsvLine(lines[1]);
        for (Integer i = 0; i < headers.size() && i < values.size(); i++) {
            if (headers[i].trim().equalsIgnoreCase(fieldName)) {
                String v = values[i].trim();
                return String.isBlank(v) ? null : v;
            }
        }
        return null;
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
