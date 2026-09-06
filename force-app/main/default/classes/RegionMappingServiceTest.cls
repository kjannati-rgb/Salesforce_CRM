@isTest
private class RegionMappingServiceTest {

    @isTest
    static void mapsKnownCountriesAndFallsBackForUnknown() {
        System.assertEquals('EMEA', RegionMappingService.regionFor('United Kingdom'), 'UK is EMEA');
        System.assertEquals('North America', RegionMappingService.regionFor('United States'), 'US is North America');
        System.assertEquals('APAC', RegionMappingService.regionFor('Japan'), 'Japan is APAC');
        System.assertEquals('LATAM', RegionMappingService.regionFor('Brazil'), 'Brazil is LATAM');
        System.assertEquals(RegionMappingService.UNCLASSIFIED, RegionMappingService.regionFor(null), 'blank input is unclassified');
        System.assertEquals(RegionMappingService.UNCLASSIFIED, RegionMappingService.regionFor(''), 'empty string is unclassified');
        System.assertEquals(RegionMappingService.UNCLASSIFIED, RegionMappingService.regionFor('Nonexistent Country XYZ'),
            'a country with no CMDT record is unclassified rather than throwing');
    }
}
