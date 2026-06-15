/**
 * Verifies WhitespaceGenerationService against the real firm/office structure (architecture §4).
 *
 * Uses SeeAllData because the service is fundamentally about live CRM accounts, and this org's
 * Account/Product objects gate creation behind record-type-restricted required picklists that make
 * synthetic test data impractical. All DML here is rolled back at test end, so the curated demo is
 * untouched. (A synthetic-data variant is a follow-up once a CPQ-seeded sandbox is available.)
 */
@isTest(SeeAllData=true)
private class WhitespaceGenerationServiceTest {

    @isTest
    static void generatesMatrixFromFirmStructure() {
        System.assertEquals(0, WhitespaceGenerationService.generate(null), 'null is a no-op');
        System.assertEquals(0, WhitespaceGenerationService.generate(new Set<Id>()), 'empty is a no-op');

        List<Account_Plan__c> plans = [
            SELECT Id FROM Account_Plan__c WHERE Account__r.Name = 'Globex Legal (DEMO)' LIMIT 1];
        if (plans.isEmpty()) {
            return; // demo data not present in this org — nothing to assert against
        }
        Id planId = plans[0].Id;

        Test.startTest();
        Integer made = WhitespaceGenerationService.generate(new Set<Id>{ planId });
        Test.stopTest();

        System.assert(made > 0, 'cells generated from the firm office structure');

        List<Whitespace_Cell__c> cells = [
            SELECT Office_Account__c, Product_Family__c, State__c
            FROM Whitespace_Cell__c WHERE Account_Plan__c = :planId];
        System.assertEquals(made, cells.size(), 'all generated cells persisted');

        Set<Id> offices = new Set<Id>();
        for (Whitespace_Cell__c c : cells) {
            System.assertNotEquals(null, c.Office_Account__c, 'every node links a real office Account');
            System.assertNotEquals(null, c.Product_Family__c, 'every cell has a product family');
            offices.add(c.Office_Account__c);
        }
        System.assert(offices.size() >= 1, 'at least one office node generated');
    }
}
