/**
 * Maps Account.BillingCountry to a macro region (EMEA / North America / APAC / LATAM) via
 * Country_Region__mdt — the org's established CMDT-driven taxonomy pattern, same shape as
 * FirmRollupService.resolveGroup() / Product_Family_Group__mdt. One shared service so the White-Space
 * Matrix and Firm Sales Summary can't drift into two different regional groupings.
 */
public with sharing class RegionMappingService {

    @TestVisible private static final String UNCLASSIFIED = 'Unclassified';

    private static Map<String, String> regionByCountry;

    private static Map<String, String> countryMap() {
        if (regionByCountry == null) {
            regionByCountry = new Map<String, String>();
            for (Country_Region__mdt m : Country_Region__mdt.getAll().values()) {
                if (String.isNotBlank(m.Country__c) && String.isNotBlank(m.Region__c)) {
                    regionByCountry.put(m.Country__c, m.Region__c);
                }
            }
        }
        return regionByCountry;
    }

    /** @return the region for a BillingCountry value, or 'Unclassified' if blank or not in the CMDT. */
    public static String regionFor(String billingCountry) {
        if (String.isBlank(billingCountry)) {
            return UNCLASSIFIED;
        }
        String r = countryMap().get(billingCountry);
        return (r == null) ? UNCLASSIFIED : r;
    }
}
