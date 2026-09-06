/**
 * REV-69 — coverage for LexProCoverageController.
 * Custom metadata records are visible in tests, so the deployed seed set is
 * queried directly; we assert the config is returned and well-formed.
 */
@isTest
private class LexProCoverageControllerTest {

    @isTest
    static void returnsCoverageConfig() {
        Test.startTest();
        List<LexPRO_Coverage__mdt> rows = LexProCoverageController.getCoverageConfig();
        Test.stopTest();

        System.assertNotEquals(null, rows, 'Coverage config should not be null');

        // Every row must declare its Type so the LWC can split regions vs work areas.
        for (LexPRO_Coverage__mdt row : rows) {
            System.assertNotEquals(
                null, row.Type__c,
                'Each LexPRO_Coverage row should have a Type (Region or WorkArea): ' + row.DeveloperName
            );
        }
    }
}
