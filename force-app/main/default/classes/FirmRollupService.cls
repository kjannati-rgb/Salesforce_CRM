/**
 * FSS §5 — maintenance engine. Recomputes persisted USD rollups for a small set of firms.
 *
 * Accurate + performant: aggregate SOQL only, per firm, so each query's grouped-row count stays
 * tiny and bounded. Headline aggregates at YEAR×MONTH grain (accurate dated USD; ~2 stages × 3
 * currencies × N years × 12 months — safely under the 2,000 GROUP-BY-row cap). The group/family
 * aggregate runs at YEAR grain only: a 28k-opp firm grouped by family×type×currency×month could
 * exceed 2,000 grouped rows, so we drop month there and convert at mid-year. Group VALUE is only
 * required to be ≈ firm net (the exact, summable group metric is the Items count); headline value
 * keeps full monthly precision.
 *
 * All currency conversion is user-independent via CurrencyConvUSD (renders USD for GBP users and
 * in automation). without sharing so aggregates see every child row regardless of running user.
 */
public without sharing class FirmRollupService {

    public static final String STAGE_WON  = 'Closed Won';
    public static final String STAGE_CANC = 'Closed Won - Cancellation';
    private static final String DEFAULT_GROUP = 'Other / POS / Reports';

    // recursion / re-entry guard: service DML on Account must never re-drive enqueue.
    public static Boolean isRunning = false;

    // cached config
    static Integer fyStartMonth;
    static Map<String, String> groupMap;   // family||ptype -> commercial group

    // ---- entry points ----
    public static void recalculateFirm(Id firmId) {
        recalculateFirms(new Set<Id>{ firmId });
    }

    public static void recalculateFirms(Set<Id> firmIdsIn) {
        Set<Id> firmIds = new Set<Id>();
        for (Id fid : firmIdsIn) { if (fid != null) firmIds.add(fid); }
        if (firmIds.isEmpty()) return;

        Boolean priorRunning = isRunning;
        isRunning = true;
        try {
            initConfig();
            Date today = Date.today();
            Integer currentFY = fiscalYearOf(today.year(), today.month());
            Integer priorFY = currentFY - 1;
            Date t12mStart = today.addMonths(-12);

            Map<Id, Headline> headlines = new Map<Id, Headline>();
            Map<Id, Map<String, GroupAcc>> groupsByFirm = new Map<Id, Map<String, GroupAcc>>();
            for (Id fid : firmIds) {
                headlines.put(fid, new Headline());
                groupsByFirm.put(fid, new Map<String, GroupAcc>());
            }

            computeHeadline(firmIds, headlines, currentFY, priorFY);
            computeHeadlineT12M(firmIds, headlines, t12mStart);
            computeSubs(firmIds, headlines, today);
            computeGroups(firmIds, groupsByFirm, currentFY, priorFY, null);          // all-time/CFY/PFY
            computeGroups(firmIds, groupsByFirm, currentFY, priorFY, t12mStart);     // T12M overlay

            writeResults(firmIds, headlines, groupsByFirm);
        } finally {
            isRunning = priorRunning;
        }
    }

    // ---- headline (year×month) ----
    static void computeHeadline(Set<Id> firmIds, Map<Id, Headline> headlines,
                                Integer currentFY, Integer priorFY) {
        for (AggregateResult ar : [
                SELECT Ultimate_Account__c fid, StageName st, CurrencyIsoCode iso,
                       CALENDAR_YEAR(CloseDate) yr, CALENDAR_MONTH(CloseDate) mo,
                       SUM(Amount) v, COUNT(Id) c
                FROM Opportunity
                WHERE Ultimate_Account__c IN :firmIds
                  AND StageName IN (:STAGE_WON, :STAGE_CANC)
                GROUP BY Ultimate_Account__c, StageName, CurrencyIsoCode,
                         CALENDAR_YEAR(CloseDate), CALENDAR_MONTH(CloseDate)]) {
            Id fid = (Id) ar.get('fid');
            Headline h = headlines.get(fid);
            if (h == null) continue;
            String st = (String) ar.get('st');
            Integer yr = toInt(ar.get('yr'));
            Integer mo = toInt(ar.get('mo'));
            Decimal usd = CurrencyConvUSD.toUSD((Decimal) ar.get('v'), (String) ar.get('iso'), firstOfMonth(yr, mo));
            Integer c = toInt(ar.get('c'));
            Boolean isWon = STAGE_WON.equals(st);
            Boolean isCanc = STAGE_CANC.equals(st);

            h.allTimeValue += usd;
            if (isWon)  h.allTimeWonCount += c;
            if (isCanc) { h.cancelValue += usd; h.cancelCount += c; }

            Integer fy = (yr == null) ? null : fiscalYearOf(yr, mo == null ? 1 : mo);
            if (fy == currentFY) { h.cfyValue += usd; if (isWon) h.cfyWonCount += c; }
            else if (fy == priorFY) { h.pfyValue += usd; if (isWon) h.pfyWonCount += c; }
        }
    }

    static void computeHeadlineT12M(Set<Id> firmIds, Map<Id, Headline> headlines, Date t12mStart) {
        for (AggregateResult ar : [
                SELECT Ultimate_Account__c fid, StageName st, CurrencyIsoCode iso,
                       CALENDAR_YEAR(CloseDate) yr, CALENDAR_MONTH(CloseDate) mo,
                       SUM(Amount) v, COUNT(Id) c
                FROM Opportunity
                WHERE Ultimate_Account__c IN :firmIds
                  AND StageName IN (:STAGE_WON, :STAGE_CANC)
                  AND CloseDate >= :t12mStart
                GROUP BY Ultimate_Account__c, StageName, CurrencyIsoCode,
                         CALENDAR_YEAR(CloseDate), CALENDAR_MONTH(CloseDate)]) {
            Id fid = (Id) ar.get('fid');
            Headline h = headlines.get(fid);
            if (h == null) continue;
            Decimal usd = CurrencyConvUSD.toUSD((Decimal) ar.get('v'), (String) ar.get('iso'),
                                                firstOfMonth(toInt(ar.get('yr')), toInt(ar.get('mo'))));
            h.t12mValue += usd;
            if (STAGE_WON.equals((String) ar.get('st'))) h.t12mWonCount += toInt(ar.get('c'));
        }
    }

    static void computeSubs(Set<Id> firmIds, Map<Id, Headline> headlines, Date today) {
        // Active = start<=today, end>=today, parent!=null, NOT terminated (amended-away originals stay
        // in-window) and NOT a bundle component (those are $0 child lines; the bundle parent carries
        // the value). So the count = currently-active, non-terminated, distinct subscriptions.
        for (AggregateResult ar : [
                SELECT Ultimate_Parent__c fid, CurrencyIsoCode iso,
                       SUM(SBQQ__NetPrice__c) v, COUNT(Id) c
                FROM SBQQ__Subscription__c
                WHERE Ultimate_Parent__c IN :firmIds
                  AND SBQQ__StartDate__c <= :today AND SBQQ__EndDate__c >= :today
                  AND SBQQ__TerminatedDate__c = null AND SBQQ__Bundled__c = false
                GROUP BY Ultimate_Parent__c, CurrencyIsoCode]) {
            Id fid = (Id) ar.get('fid');
            Headline h = headlines.get(fid);
            if (h == null) continue;
            h.activeSubCount += toInt(ar.get('c'));
            // snapshot metric -> value active subs at today's rate
            h.activeSubValue += CurrencyConvUSD.toUSD((Decimal) ar.get('v'), (String) ar.get('iso'), today);
        }
    }

    // ---- groups (year grain). t12mStart!=null -> only accumulate into the T12M bucket. ----
    static void computeGroups(Set<Id> firmIds, Map<Id, Map<String, GroupAcc>> groupsByFirm,
                              Integer currentFY, Integer priorFY, Date t12mStart) {
        String soql =
            'SELECT Opportunity.Ultimate_Account__c fid, Product2.Family fam, Product2.Product_Type__c pt, ' +
            'CurrencyIsoCode iso, Opportunity.StageName st, CALENDAR_YEAR(Opportunity.CloseDate) yr, ' +
            'SUM(TotalPrice) v, SUM(Annual_Contract_Value__c) acv, COUNT(Id) items ' +
            'FROM OpportunityLineItem ' +
            'WHERE Opportunity.Ultimate_Account__c IN :firmIds ' +
            'AND Opportunity.StageName IN (:STAGE_WON, :STAGE_CANC) ' +
            (t12mStart != null ? 'AND Opportunity.CloseDate >= :t12mStart ' : '') +
            'GROUP BY Opportunity.Ultimate_Account__c, Product2.Family, Product2.Product_Type__c, ' +
            'CurrencyIsoCode, Opportunity.StageName, CALENDAR_YEAR(Opportunity.CloseDate)';
        for (AggregateResult ar : Database.query(soql)) {
            Id fid = (Id) ar.get('fid');
            Map<String, GroupAcc> gm = groupsByFirm.get(fid);
            if (gm == null) continue;
            String grp = resolveGroup((String) ar.get('fam'), (String) ar.get('pt'));
            Integer yr = toInt(ar.get('yr'));
            Date asOf = (yr == null) ? Date.today() : Date.newInstance(yr, 7, 1); // mid-year dated rate
            Decimal usd = CurrencyConvUSD.toUSD((Decimal) ar.get('v'), (String) ar.get('iso'), asOf);
            Decimal acvUsd = CurrencyConvUSD.toUSD((Decimal) ar.get('acv'), (String) ar.get('iso'), asOf);
            // net: a cancellation line must reduce the total even if stored positive (§4a guard)
            if (STAGE_CANC.equals((String) ar.get('st'))) {
                if (usd > 0) usd = -usd;
                if (acvUsd > 0) acvUsd = -acvUsd;
            }
            Integer items = toInt(ar.get('items'));

            GroupAcc g = gm.get(grp);
            if (g == null) { g = new GroupAcc(); gm.put(grp, g); }

            if (t12mStart != null) {
                g.t12mValue += usd; g.t12mItems += items; g.t12mAcv += acvUsd;
            } else {
                g.allTimeValue += usd; g.allTimeItems += items; g.allTimeAcv += acvUsd;
                Integer fy = (yr == null) ? null : fiscalYearOf(yr, 7);
                if (fy == currentFY) { g.cfyValue += usd; g.cfyItems += items; g.cfyAcv += acvUsd; }
                else if (fy == priorFY) { g.pfyValue += usd; g.pfyItems += items; g.pfyAcv += acvUsd; }
            }
        }
    }

    // ---- persist ----
    static void writeResults(Set<Id> firmIds, Map<Id, Headline> headlines,
                             Map<Id, Map<String, GroupAcc>> groupsByFirm) {
        Datetime now = Datetime.now();
        List<Account> accts = new List<Account>();
        for (Id fid : firmIds) {
            Headline h = headlines.get(fid);
            // firm ACV per period = Σ group ACV (line-grain), so headline = Σ groups by construction
            Decimal acvAll = 0, acvCfy = 0, acvPfy = 0, acvT12m = 0;
            for (GroupAcc g : groupsByFirm.get(fid).values()) {
                acvAll += g.allTimeAcv; acvCfy += g.cfyAcv; acvPfy += g.pfyAcv; acvT12m += g.t12mAcv;
            }
            accts.add(new Account(
                Id = fid,
                Firm_Won_Value_AllTime_USD__c = round2(h.allTimeValue),
                Firm_Won_Count_AllTime__c = h.allTimeWonCount,
                Firm_Cancellation_Value_AllTime_USD__c = round2(h.cancelValue),
                Firm_Cancellation_Count_AllTime__c = h.cancelCount,
                Firm_Won_Value_CFY_USD__c = round2(h.cfyValue),
                Firm_Won_Count_CFY__c = h.cfyWonCount,
                Firm_Won_Value_PFY_USD__c = round2(h.pfyValue),
                Firm_Won_Count_PFY__c = h.pfyWonCount,
                Firm_Won_Value_T12M_USD__c = round2(h.t12mValue),
                Firm_Won_Count_T12M__c = h.t12mWonCount,
                Firm_Won_ACV_AllTime_USD__c = round2(acvAll),
                Firm_Won_ACV_CFY_USD__c = round2(acvCfy),
                Firm_Won_ACV_PFY_USD__c = round2(acvPfy),
                Firm_Won_ACV_T12M_USD__c = round2(acvT12m),
                Firm_Active_Subscriptions__c = h.activeSubCount,
                Firm_Active_Sub_Value_USD__c = round2(h.activeSubValue),
                Firm_Rollup_Last_Refreshed__c = now
            ));
        }
        for (Database.SaveResult sr : Database.update(accts, false)) {
            if (!sr.isSuccess()) System.debug(LoggingLevel.WARN, 'FSS firm update failed: ' + sr.getErrors());
        }

        // group child rows: upsert non-zero, delete-on-zero
        List<Firm_Product_Group_Rollup_USD__c> toUpsert = new List<Firm_Product_Group_Rollup_USD__c>();
        Map<Id, Set<String>> liveKeysByFirm = new Map<Id, Set<String>>();
        for (Id fid : firmIds) {
            liveKeysByFirm.put(fid, new Set<String>());
            for (String grp : groupsByFirm.get(fid).keySet()) {
                GroupAcc g = groupsByFirm.get(fid).get(grp);
                if (!g.hasData()) continue;
                String key = fid + '|' + grp;
                liveKeysByFirm.get(fid).add(key);
                toUpsert.add(new Firm_Product_Group_Rollup_USD__c(
                    Firm__c = fid,
                    Commercial_Group__c = grp,
                    Firm_Group_Key__c = key,
                    Won_Value_AllTime_USD__c = round2(g.allTimeValue),
                    Won_Items_AllTime__c = g.allTimeItems,
                    Won_Value_CFY_USD__c = round2(g.cfyValue),
                    Won_Items_CFY__c = g.cfyItems,
                    Won_Value_PFY_USD__c = round2(g.pfyValue),
                    Won_Items_PFY__c = g.pfyItems,
                    Won_Value_T12M_USD__c = round2(g.t12mValue),
                    Won_Items_T12M__c = g.t12mItems,
                    Won_ACV_AllTime_USD__c = round2(g.allTimeAcv),
                    Won_ACV_CFY_USD__c = round2(g.cfyAcv),
                    Won_ACV_PFY_USD__c = round2(g.pfyAcv),
                    Won_ACV_T12M_USD__c = round2(g.t12mAcv),
                    Last_Refreshed__c = now
                ));
            }
        }
        if (!toUpsert.isEmpty()) {
            for (Database.UpsertResult ur : Database.upsert(toUpsert,
                    Firm_Product_Group_Rollup_USD__c.Firm_Group_Key__c, false)) {
                if (!ur.isSuccess()) System.debug(LoggingLevel.WARN, 'FSS group upsert failed: ' + ur.getErrors());
            }
        }

        List<Firm_Product_Group_Rollup_USD__c> toDelete = new List<Firm_Product_Group_Rollup_USD__c>();
        for (Firm_Product_Group_Rollup_USD__c row : [
                SELECT Id, Firm__c, Firm_Group_Key__c
                FROM Firm_Product_Group_Rollup_USD__c WHERE Firm__c IN :firmIds]) {
            Set<String> live = liveKeysByFirm.get(row.Firm__c);
            if (live == null || !live.contains(row.Firm_Group_Key__c)) toDelete.add(row);
        }
        if (!toDelete.isEmpty()) {
            for (Database.DeleteResult dr : Database.delete(toDelete, false)) {
                if (!dr.isSuccess()) System.debug(LoggingLevel.WARN, 'FSS group delete failed: ' + dr.getErrors());
            }
        }
    }

    // ---- group resolution (§6) ----
    public static String resolveGroup(String family, String ptype1) {
        if (groupMap == null) initConfig();
        String pt = (ptype1 == null) ? '' : ptype1;
        String g = groupMap.get(family + '||' + pt);
        if (g == null) g = groupMap.get(family + '||');     // (Family, blank) family-default
        if (g == null) { System.debug(LoggingLevel.WARN, 'FSS unmatched family/type: ' + family + '/' + pt); g = DEFAULT_GROUP; }
        return g;
    }

    static void initConfig() {
        if (fyStartMonth == null) {
            fyStartMonth = [SELECT FiscalYearStartMonth FROM Organization LIMIT 1].FiscalYearStartMonth;
        }
        if (groupMap == null) {
            groupMap = new Map<String, String>();
            for (Product_Family_Group__mdt m : Product_Family_Group__mdt.getAll().values()) {
                String pt = (m.Product_Type_1__c == null) ? '' : m.Product_Type_1__c;
                groupMap.put(m.Family__c + '||' + pt, m.Commercial_Group__c);
            }
        }
    }

    @TestVisible
    static void setConfigForTest(Integer startMonth, Map<String, String> gmap) {
        fyStartMonth = startMonth; groupMap = gmap;
    }

    // ---- helpers ----
    static Integer fiscalYearOf(Integer yr, Integer mo) {
        if (yr == null) return null;
        if (fyStartMonth == null || fyStartMonth == 1) return yr;            // org here: FY = calendar year
        return (mo >= fyStartMonth) ? yr : yr - 1;                            // named by start year otherwise
    }
    static Date firstOfMonth(Integer yr, Integer mo) {
        if (yr == null) return Date.today();
        return Date.newInstance(yr, (mo == null ? 1 : mo), 1);
    }
    static Integer toInt(Object o) { return (o == null) ? 0 : (Integer) o; }
    static Decimal round2(Decimal d) { return (d == null) ? 0 : d.setScale(2, System.RoundingMode.HALF_UP); }

    // ---- accumulators ----
    public class Headline {
        public Decimal allTimeValue = 0; public Integer allTimeWonCount = 0;
        public Decimal cancelValue = 0;  public Integer cancelCount = 0;
        public Decimal cfyValue = 0;     public Integer cfyWonCount = 0;
        public Decimal pfyValue = 0;     public Integer pfyWonCount = 0;
        public Decimal t12mValue = 0;    public Integer t12mWonCount = 0;
        public Integer activeSubCount = 0; public Decimal activeSubValue = 0;
    }
    public class GroupAcc {
        public Decimal allTimeValue = 0; public Integer allTimeItems = 0; public Decimal allTimeAcv = 0;
        public Decimal cfyValue = 0;     public Integer cfyItems = 0;     public Decimal cfyAcv = 0;
        public Decimal pfyValue = 0;     public Integer pfyItems = 0;     public Decimal pfyAcv = 0;
        public Decimal t12mValue = 0;    public Integer t12mItems = 0;    public Decimal t12mAcv = 0;
        public Boolean hasData() {
            return allTimeItems != 0 || cfyItems != 0 || pfyItems != 0 || t12mItems != 0
                || allTimeValue != 0 || cfyValue != 0 || pfyValue != 0 || t12mValue != 0;
        }
    }
}
