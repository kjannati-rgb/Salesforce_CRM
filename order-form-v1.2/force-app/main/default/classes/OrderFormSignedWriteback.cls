/**
 * REV Order Form v1.2 - post-signing write-back, replacing the Adobe Sign package's
 * data mapping (whose object-mapping stage cannot traverse the custom Quote__c lookup
 * in this package version - every Fully_Qualified_API__c form fails, see runbook
 * 2026-08-20). Invoked by the Agreement_Signed_Writeback flow when an agreement
 * reaches Signed. Idempotent: safe to re-run on the same agreement.
 */
public with sharing class OrderFormSignedWriteback {

    public class Request {
        @InvocableVariable(label='Agreement Id' required=true)
        public Id agreementId;
    }

    @InvocableMethod(
        label='Order Form signed write-back'
        description='Stamps the customer signed date on the quote and files the signed PDF on it.')
    public static void run(List<Request> requests) {
        Set<Id> agreementIds = new Set<Id>();
        for (Request req : requests) {
            agreementIds.add(req.agreementId);
        }
        List<echosign_dev1__SIGN_Agreement__c> agreements = [
            SELECT Id, Quote__c, echosign_dev1__DateSignedDate__c
            FROM echosign_dev1__SIGN_Agreement__c
            WHERE Id IN :agreementIds AND Quote__c != null
        ];
        if (agreements.isEmpty()) {
            return;
        }

        Map<Id, SBQQ__Quote__c> quoteUpdates = new Map<Id, SBQQ__Quote__c>();
        for (echosign_dev1__SIGN_Agreement__c ag : agreements) {
            Date signed = ag.echosign_dev1__DateSignedDate__c != null
                ? ag.echosign_dev1__DateSignedDate__c
                : Date.today();
            quoteUpdates.put(ag.Quote__c, new SBQQ__Quote__c(Id = ag.Quote__c, Customer_Signed_Date__c = signed));
        }
        update quoteUpdates.values();

        // file the signed PDF on the quote (skip when an identically named file is already there)
        List<Attachment> pdfs = [
            SELECT Id, Name, Body, ParentId
            FROM Attachment
            WHERE ParentId IN :agreements AND Name LIKE '%signed.pdf'
            ORDER BY CreatedDate DESC
        ];
        Map<Id, Attachment> newestByAgreement = new Map<Id, Attachment>();
        for (Attachment att : pdfs) {
            if (!newestByAgreement.containsKey(att.ParentId)) {
                newestByAgreement.put(att.ParentId, att);
            }
        }
        Set<String> wantedTitles = new Set<String>();
        for (Attachment att : newestByAgreement.values()) {
            wantedTitles.add(att.Name.removeEnd('.pdf'));
        }
        Set<String> existingTitles = new Set<String>();
        for (ContentDocumentLink link : [
            SELECT ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :quoteUpdates.keySet()
        ]) {
            existingTitles.add(link.ContentDocument.Title);
        }

        List<ContentVersion> files = new List<ContentVersion>();
        for (echosign_dev1__SIGN_Agreement__c ag : agreements) {
            Attachment pdf = newestByAgreement.get(ag.Id);
            if (pdf == null || existingTitles.contains(pdf.Name.removeEnd('.pdf'))) {
                continue;
            }
            files.add(new ContentVersion(
                Title = pdf.Name.removeEnd('.pdf'),
                PathOnClient = pdf.Name,
                VersionData = pdf.Body,
                FirstPublishLocationId = ag.Quote__c));
        }
        if (!files.isEmpty()) {
            insert files;
        }

        // signer-typed PO -> quote, via a direct Adobe REST call (needs a callout, so queued);
        // silently skipped until an integration key is configured in Order_Form_Adobe_Settings__c
        if (OrderFormPoWriteback.isConfigured()) {
            for (echosign_dev1__SIGN_Agreement__c ag : agreements) {
                System.enqueueJob(new OrderFormPoWriteback(ag.Id));
            }
        }
    }
}
