/**
 * FSS §3a — user-independent currency conversion to the reporting currency (USD).
 *
 * Why not convertCurrency(): that converts to the RUNNING USER's currency. Commercial/CSM
 * users are GBP today and the feature must always render USD, in triggers, batch and on-screen.
 * So we read the org's rate tables directly and apply a currency-pair ratio that is
 * independent of both the running user and the corporate currency.
 *
 *   amount_USD = amount_native × rate(target, asOf) / rate(native, asOf)
 *
 * SF rate semantics: ConversionRate = units of that currency per 1 unit of the CORPORATE
 * currency. The result is a ratio of two currencies' rates, so it is unchanged when the
 * corporate currency flips GBP→USD (rates re-base, the ratio holds) — no cutover action.
 *
 * Basis (CMDT Rollup_Setting__mdt): Dated (close-date DatedConversionRate, static fallback) | Static.
 * Tables are loaded once per transaction; @TestVisible hooks allow synthetic injection.
 */
public without sharing class CurrencyConvUSD {

    public class CurrencyConvException extends Exception {}

    /** One DatedConversionRate row, effective over [startDate, nextStart). */
    public class DatedRate {
        public String iso; public Date startDate; public Date nextStart; public Decimal rate;
        public DatedRate(String iso, Date startDate, Date nextStart, Decimal rate) {
            this.iso = iso; this.startDate = startDate; this.nextStart = nextStart; this.rate = rate;
        }
    }

    @TestVisible static Map<String, Decimal> staticRates;          // iso -> current static rate
    @TestVisible static Map<String, List<DatedRate>> datedRates;   // iso -> dated rows
    @TestVisible static String targetIso;                          // reporting currency, default USD
    @TestVisible static String defaultBasis;                       // 'Dated' | 'Static'
    @TestVisible static Boolean loaded = false;

    // ---- configuration ----
    @TestVisible
    static void load() {
        if (loaded && staticRates != null) return;
        staticRates = new Map<String, Decimal>();
        datedRates = new Map<String, List<DatedRate>>();

        for (CurrencyType ct : [SELECT IsoCode, ConversionRate FROM CurrencyType WHERE IsActive = true]) {
            staticRates.put(ct.IsoCode, ct.ConversionRate);
        }
        for (DatedConversionRate d : [
                SELECT IsoCode, StartDate, NextStartDate, ConversionRate FROM DatedConversionRate]) {
            if (!datedRates.containsKey(d.IsoCode)) datedRates.put(d.IsoCode, new List<DatedRate>());
            datedRates.get(d.IsoCode).add(new DatedRate(d.IsoCode, d.StartDate, d.NextStartDate, d.ConversionRate));
        }

        Rollup_Setting__mdt cfg = getConfig();
        targetIso = (cfg != null && String.isNotBlank(cfg.Target_Currency__c)) ? cfg.Target_Currency__c : 'USD';
        defaultBasis = (cfg != null && String.isNotBlank(cfg.FX_Basis__c)) ? cfg.FX_Basis__c : 'Dated';
        loaded = true;
    }

    static Rollup_Setting__mdt getConfig() {
        Rollup_Setting__mdt c = Rollup_Setting__mdt.getInstance('Default');
        if (c != null) return c;
        for (Rollup_Setting__mdt r : Rollup_Setting__mdt.getAll().values()) return r; // any record
        return null;
    }

    /** Inject synthetic rate tables (corp-flip / multi-currency tests). */
    @TestVisible
    static void loadForTest(Map<String, Decimal> stat, Map<String, List<DatedRate>> dated,
                            String tgt, String basis) {
        staticRates = (stat != null) ? stat : new Map<String, Decimal>();
        datedRates = (dated != null) ? dated : new Map<String, List<DatedRate>>();
        targetIso = (tgt != null) ? tgt : 'USD';
        defaultBasis = (basis != null) ? basis : 'Dated';
        loaded = true;
    }

    // ---- public API ----
    public static String getTargetCurrency() { load(); return targetIso; }
    public static String getFxBasis()        { load(); return defaultBasis; }

    /** Convert using the configured basis. */
    public static Decimal toUSD(Decimal amt, String iso, Date asOf) {
        return toUSD(amt, iso, asOf, null);
    }

    /** Convert with an explicit basis override ('Dated' | 'Static'); null = configured. */
    public static Decimal toUSD(Decimal amt, String iso, Date asOf, String basisOverride) {
        if (amt == null) return 0;
        load();
        String basis = (basisOverride != null) ? basisOverride : defaultBasis;
        // Pass-through: native already in target (USD opps unchanged on any basis).
        if (iso == null || iso == targetIso) return amt.setScale(2, System.RoundingMode.HALF_UP);

        Decimal rTarget = rateFor(targetIso, asOf, basis);
        Decimal rIso = rateFor(iso, asOf, basis);
        if (rIso == null || rIso == 0) {
            throw new CurrencyConvException('No usable FX rate for ' + iso + ' as of ' + asOf);
        }
        return (amt * rTarget / rIso).setScale(2, System.RoundingMode.HALF_UP);
    }

    /** Rate of `iso` per 1 corporate unit, on `asOf` for Dated (static fallback), else static. */
    @TestVisible
    static Decimal rateFor(String iso, Date asOf, String basis) {
        if ('Dated'.equalsIgnoreCase(basis) && asOf != null) {
            List<DatedRate> rows = datedRates.get(iso);
            if (rows != null) {
                for (DatedRate dr : rows) {
                    Boolean afterStart = (dr.startDate == null) || (asOf >= dr.startDate);
                    Boolean beforeNext = (dr.nextStart == null) || (asOf < dr.nextStart);
                    if (afterStart && beforeNext) return dr.rate;
                }
            }
            // not covered by a dated row -> fall back to static
        }
        Decimal s = staticRates.get(iso);
        if (s != null) return s;
        throw new CurrencyConvException('No FX rate configured for currency ' + iso);
    }
}
