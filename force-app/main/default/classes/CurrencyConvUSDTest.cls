@isTest
private class CurrencyConvUSDTest {

    static Map<String, List<CurrencyConvUSD.DatedRate>> noDated() {
        return new Map<String, List<CurrencyConvUSD.DatedRate>>();
    }

    @isTest static void staticConversionAndPassthrough() {
        CurrencyConvUSD.loadForTest(new Map<String, Decimal>{ 'GBP' => 1, 'USD' => 2, 'EUR' => 4 },
                                    noDated(), 'USD', 'Static');
        System.assertEquals(200, CurrencyConvUSD.toUSD(100, 'GBP', Date.today()), 'GBP×rate(USD)/rate(GBP)');
        System.assertEquals(50, CurrencyConvUSD.toUSD(100, 'EUR', Date.today()), 'EUR÷2');
        System.assertEquals(100, CurrencyConvUSD.toUSD(100, 'USD', Date.today()), 'USD pass-through');
        System.assertEquals(0, CurrencyConvUSD.toUSD(null, 'GBP', Date.today()), 'null amount -> 0');
    }

    @isTest static void datedSelectionWithStaticFallback() {
        Map<String, List<CurrencyConvUSD.DatedRate>> dated = noDated();
        dated.put('USD', new List<CurrencyConvUSD.DatedRate>{
            new CurrencyConvUSD.DatedRate('USD', Date.newInstance(2020, 1, 1), Date.newInstance(2021, 1, 1), 3)
        });
        CurrencyConvUSD.loadForTest(new Map<String, Decimal>{ 'GBP' => 1, 'USD' => 2 }, dated, 'USD', 'Dated');
        // inside dated window -> rate(USD)=3
        System.assertEquals(300, CurrencyConvUSD.toUSD(100, 'GBP', Date.newInstance(2020, 6, 1)), 'dated rate used');
        // outside window -> static USD=2 fallback
        System.assertEquals(200, CurrencyConvUSD.toUSD(100, 'GBP', Date.newInstance(2023, 1, 1)), 'static fallback');
    }

    @isTest static void corporateCurrencyFlipInvariance() {
        // Corp = GBP
        CurrencyConvUSD.loadForTest(new Map<String, Decimal>{ 'GBP' => 1, 'USD' => 2, 'EUR' => 4 }, noDated(), 'USD', 'Static');
        Decimal gbpUnderGbpCorp = CurrencyConvUSD.toUSD(100, 'GBP', Date.today());
        Decimal eurUnderGbpCorp = CurrencyConvUSD.toUSD(100, 'EUR', Date.today());
        // Corp flips to USD (every rate re-based by ÷2): GBP=0.5, USD=1, EUR=2
        CurrencyConvUSD.loadForTest(new Map<String, Decimal>{ 'GBP' => 0.5, 'USD' => 1, 'EUR' => 2 }, noDated(), 'USD', 'Static');
        System.assertEquals(gbpUnderGbpCorp, CurrencyConvUSD.toUSD(100, 'GBP', Date.today()), 'GBP→USD invariant under corp flip');
        System.assertEquals(eurUnderGbpCorp, CurrencyConvUSD.toUSD(100, 'EUR', Date.today()), 'EUR→USD invariant under corp flip');
    }

    @isTest static void unknownCurrencyThrows() {
        CurrencyConvUSD.loadForTest(new Map<String, Decimal>{ 'GBP' => 1, 'USD' => 2 }, noDated(), 'USD', 'Static');
        Boolean threw = false;
        try { CurrencyConvUSD.toUSD(100, 'ZZZ', Date.today()); }
        catch (CurrencyConvUSD.CurrencyConvException e) { threw = true; }
        System.assert(threw, 'unknown currency should throw');
    }

    @isTest static void liveLoadPathFromOrg() {
        // No injection -> exercises load() against real CurrencyType/DatedConversionRate/CMDT.
        Test.startTest();
        Decimal usd = CurrencyConvUSD.toUSD(100, 'USD', Date.today()); // pass-through regardless of rates
        String tgt = CurrencyConvUSD.getTargetCurrency();
        String basis = CurrencyConvUSD.getFxBasis();
        Test.stopTest();
        System.assertEquals(100, usd, 'USD native pass-through on live load');
        System.assertEquals('USD', tgt, 'target currency from CMDT');
        System.assert(basis == 'Dated' || basis == 'Static', 'basis resolved');
    }
}
