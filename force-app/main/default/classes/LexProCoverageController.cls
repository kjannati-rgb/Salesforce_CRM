/**
 * REV-69 — LexPRO Deal Qualifier.
 * Read-only config source for the lexproQualifier LWC: returns the coverage
 * regions and work areas defined in LexPRO_Coverage__mdt so RevOps/content can
 * change "what we cover" without a deploy.
 *
 * cacheable=true enables @wire + client-side caching; the data is non-sensitive
 * config (custom metadata carries no row-level security).
 */
public with sharing class LexProCoverageController {

    @AuraEnabled(cacheable=true)
    public static List<LexPRO_Coverage__mdt> getCoverageConfig() {
        return [
            SELECT MasterLabel, DeveloperName, Type__c, Covered__c, Tier__c,
                   Sort_Order__c, Map_Top__c, Map_Left__c, Note__c
            FROM LexPRO_Coverage__mdt
            ORDER BY Sort_Order__c NULLS LAST
        ];
    }
}
