/**
 * FSS §7 — LWC read controller. with sharing; FLS/CRUD enforced on record reads.
 * Headline + group reads come from PERSISTED rollups (instant, cacheable). Office and opportunity
 * drill-downs are computed LIVE (imperative); every money figure is converted to USD via
 * CurrencyConvUSD so it renders USD regardless of the running user's currency.
 */
public with sharing class FirmSalesSummaryController {

    static final String WON = FirmRollupService.STAGE_WON;
    static final String CANC = FirmRollupService.STAGE_CANC;
    // Renewal-family Opportunity.Type values for the New/Renewal business lens (mockup toggle).
    static final List<String> RENEWAL_TYPES = new List<String>{
        'Renewal', 'Auto-Renewal', 'Repeat Business', 'Auto-Repeat Business'
    };
    static Integer fyStartMonth;

    /** SOQL fragment for the business lens. Expects a local `renewalTypes` bind var in scope. */
    static String businessClause(String businessType) { return businessClause(businessType, ''); }
    static String businessClause(String businessType, String prefix) {
        String bt = (businessType == null) ? 'all' : businessType.toLowerCase();
        if (bt == 'new') return ' AND ' + prefix + 'Type = \'New Business\'';
        if (bt == 'renewal') return ' AND ' + prefix + 'Type IN :renewalTypes';
        return '';
    }

    static Integer fiscalYearOf(Integer yr, Integer mo) {
        if (yr == null) return null;
        if (fyStartMonth == null) {
            fyStartMonth = [SELECT FiscalYearStartMonth FROM Organization LIMIT 1].FiscalYearStartMonth;
        }
        if (fyStartMonth == 1) return yr;
        return (mo >= fyStartMonth) ? yr : yr - 1;
    }

    // ---------- headline (persisted, cacheable) ----------
    @AuraEnabled(cacheable=true)
    public static SummaryDTO getSummary(Id firmId) {
        List<Account> rows = [
            SELECT Id, Name,
                   Firm_Won_Value_AllTime_USD__c, Firm_Won_Count_AllTime__c,
                   Firm_Cancellation_Value_AllTime_USD__c, Firm_Cancellation_Count_AllTime__c,
                   Firm_Won_Value_CFY_USD__c, Firm_Won_Count_CFY__c,
                   Firm_Won_Value_PFY_USD__c, Firm_Won_Count_PFY__c,
                   Firm_Won_Value_T12M_USD__c, Firm_Won_Count_T12M__c,
                   Firm_Won_ACV_AllTime_USD__c, Firm_Won_ACV_CFY_USD__c,
                   Firm_Won_ACV_PFY_USD__c, Firm_Won_ACV_T12M_USD__c,
                   Firm_Active_Subscriptions__c, Firm_Active_Sub_Value_USD__c,
                   Firm_Rollup_Last_Refreshed__c
            FROM Account WHERE Id = :firmId WITH SECURITY_ENFORCED LIMIT 1];
        if (rows.isEmpty()) throw new AuraHandledException('Firm not found or not accessible.');
        Account a = rows[0];

        SummaryDTO s = new SummaryDTO();
        s.firmId = a.Id;
        s.firmName = a.Name;
        s.targetCurrency = CurrencyConvUSD.getTargetCurrency();
        s.fxBasis = CurrencyConvUSD.getFxBasis();
        s.lastRefreshed = a.Firm_Rollup_Last_Refreshed__c;
        s.activeSubs = nz(a.Firm_Active_Subscriptions__c);
        s.activeSubValue = nzd(a.Firm_Active_Sub_Value_USD__c);
        s.cancelCount = nz(a.Firm_Cancellation_Count_AllTime__c);
        s.cancelValue = nzd(a.Firm_Cancellation_Value_AllTime_USD__c);
        s.periods = new List<PeriodDTO>{
            period('alltime', 'All-time', a.Firm_Won_Value_AllTime_USD__c, a.Firm_Won_Count_AllTime__c),
            period('cfy', 'This FY', a.Firm_Won_Value_CFY_USD__c, a.Firm_Won_Count_CFY__c),
            period('pfy', 'Last FY', a.Firm_Won_Value_PFY_USD__c, a.Firm_Won_Count_PFY__c),
            period('t12m', 'Last 12 mo', a.Firm_Won_Value_T12M_USD__c, a.Firm_Won_Count_T12M__c)
        };
        s.periods[0].acv = nzd(a.Firm_Won_ACV_AllTime_USD__c);
        s.periods[1].acv = nzd(a.Firm_Won_ACV_CFY_USD__c);
        s.periods[2].acv = nzd(a.Firm_Won_ACV_PFY_USD__c);
        s.periods[3].acv = nzd(a.Firm_Won_ACV_T12M_USD__c);
        return s;
    }

    // ---------- groups (persisted, cacheable) ----------
    @AuraEnabled(cacheable=true)
    public static List<GroupDTO> getGroupBreakdown(Id firmId) {
        List<GroupDTO> out = new List<GroupDTO>();
        for (Firm_Product_Group_Rollup_USD__c r : [
                SELECT Commercial_Group__c,
                       Won_Value_AllTime_USD__c, Won_Items_AllTime__c, Won_ACV_AllTime_USD__c,
                       Won_Value_CFY_USD__c, Won_Items_CFY__c, Won_ACV_CFY_USD__c,
                       Won_Value_PFY_USD__c, Won_Items_PFY__c, Won_ACV_PFY_USD__c,
                       Won_Value_T12M_USD__c, Won_Items_T12M__c, Won_ACV_T12M_USD__c
                FROM Firm_Product_Group_Rollup_USD__c
                WHERE Firm__c = :firmId WITH SECURITY_ENFORCED
                ORDER BY Won_Value_AllTime_USD__c DESC NULLS LAST]) {
            GroupDTO g = new GroupDTO();
            g.name = r.Commercial_Group__c;
            g.allTimeValue = nzd(r.Won_Value_AllTime_USD__c); g.allTimeItems = nz(r.Won_Items_AllTime__c); g.allTimeAcv = nzd(r.Won_ACV_AllTime_USD__c);
            g.cfyValue = nzd(r.Won_Value_CFY_USD__c);         g.cfyItems = nz(r.Won_Items_CFY__c);         g.cfyAcv = nzd(r.Won_ACV_CFY_USD__c);
            g.pfyValue = nzd(r.Won_Value_PFY_USD__c);         g.pfyItems = nz(r.Won_Items_PFY__c);         g.pfyAcv = nzd(r.Won_ACV_PFY_USD__c);
            g.t12mValue = nzd(r.Won_Value_T12M_USD__c);       g.t12mItems = nz(r.Won_Items_T12M__c);       g.t12mAcv = nzd(r.Won_ACV_T12M_USD__c);
            out.add(g);
        }
        return out;
    }

    // ---------- unified live cross-filter view (linked widgets) ----------
    // Click an office -> headline + group panel filter to that office. Click a group -> headline +
    // office panel filter to that group. Both can stack; period + business apply throughout.
    // Group filter is opp-grain (won opps that include a line in the group). The default no-filter,
    // all-business view still uses the instant persisted reads in the LWC.
    @AuraEnabled
    public static ViewDTO getView(Id firmId, String period, String businessType, Id officeId, String commercialGroup) {
        List<String> renewalTypes = RENEWAL_TYPES;
        Date today = Date.today();
        Integer currentFY = fiscalYearOf(today.year(), today.month());
        Integer priorFY = currentFY - 1;
        Date t12mStart = today.addMonths(-12);
        String bc = businessClause(businessType);
        String officeClause = (officeId != null) ? ' AND AccountId = :officeId' : '';
        List<String> nef = new List<String>(); List<String> ept = new List<String>(); Boolean[] inclOther = new Boolean[]{ false };
        String groupClause = oppGroupFilter(commercialGroup, nef, ept, inclOther);

        Map<String, Decimal> v = new Map<String, Decimal>{ 'alltime' => 0, 'cfy' => 0, 'pfy' => 0, 't12m' => 0 };
        Map<String, Integer> w = new Map<String, Integer>{ 'alltime' => 0, 'cfy' => 0, 'pfy' => 0, 't12m' => 0 };
        Decimal cancelVal = 0; Integer cancelCnt = 0;

        for (AggregateResult ar : Database.query(
                'SELECT StageName st, CurrencyIsoCode iso, CALENDAR_YEAR(CloseDate) yr, CALENDAR_MONTH(CloseDate) mo, ' +
                'SUM(Amount) amt, COUNT(Id) c FROM Opportunity ' +
                'WHERE Ultimate_Account__c = :firmId AND StageName IN (:WON, :CANC)' + officeClause + groupClause + bc +
                ' GROUP BY StageName, CurrencyIsoCode, CALENDAR_YEAR(CloseDate), CALENDAR_MONTH(CloseDate)')) {
            String st = (String) ar.get('st');
            Integer yr = (Integer) ar.get('yr'); Integer mo = (Integer) ar.get('mo');
            Decimal usd = CurrencyConvUSD.toUSD((Decimal) ar.get('amt'), (String) ar.get('iso'),
                              (yr == null) ? today : Date.newInstance(yr, (mo == null ? 1 : mo), 1));
            Integer c = (Integer) ar.get('c');
            Boolean isWon = WON.equals(st);  // NB: not `won` — case-insensitive bind would clash with :WON
            v.put('alltime', v.get('alltime') + usd);
            if (isWon) w.put('alltime', w.get('alltime') + c);
            if (CANC.equals(st)) { cancelVal += usd; cancelCnt += c; }
            Integer fy = (yr == null) ? null : fiscalYearOf(yr, (mo == null ? 1 : mo));
            if (fy == currentFY) { v.put('cfy', v.get('cfy') + usd); if (isWon) w.put('cfy', w.get('cfy') + c); }
            else if (fy == priorFY) { v.put('pfy', v.get('pfy') + usd); if (isWon) w.put('pfy', w.get('pfy') + c); }
        }
        for (AggregateResult ar : Database.query(
                'SELECT StageName st, CurrencyIsoCode iso, CALENDAR_YEAR(CloseDate) yr, CALENDAR_MONTH(CloseDate) mo, ' +
                'SUM(Amount) amt, COUNT(Id) c FROM Opportunity ' +
                'WHERE Ultimate_Account__c = :firmId AND StageName IN (:WON, :CANC) AND CloseDate >= :t12mStart' + officeClause + groupClause + bc +
                ' GROUP BY StageName, CurrencyIsoCode, CALENDAR_YEAR(CloseDate), CALENDAR_MONTH(CloseDate)')) {
            Integer yr = (Integer) ar.get('yr'); Integer mo = (Integer) ar.get('mo');
            Decimal usd = CurrencyConvUSD.toUSD((Decimal) ar.get('amt'), (String) ar.get('iso'),
                              (yr == null) ? today : Date.newInstance(yr, (mo == null ? 1 : mo), 1));
            v.put('t12m', v.get('t12m') + usd);
            if (WON.equals((String) ar.get('st'))) w.put('t12m', w.get('t12m') + (Integer) ar.get('c'));
        }

        ViewDTO out = new ViewDTO();
        out.periods = new List<PeriodDTO>{
            period('alltime', 'All-time', v.get('alltime'), w.get('alltime')),
            period('cfy', 'This FY', v.get('cfy'), w.get('cfy')),
            period('pfy', 'Last FY', v.get('pfy'), w.get('pfy')),
            period('t12m', 'Last 12 mo', v.get('t12m'), w.get('t12m'))
        };
        out.cancelValue = cancelVal.setScale(2);
        out.cancelCount = cancelCnt;
        // active subs — filtered by office only (subs have no group/business dimension)
        Integer subCnt = 0; Decimal subVal = 0;
        for (AggregateResult ar : Database.query(
                'SELECT SUM(SBQQ__NetPrice__c) sv, COUNT(Id) sc, CurrencyIsoCode iso FROM SBQQ__Subscription__c ' +
                'WHERE Ultimate_Parent__c = :firmId AND SBQQ__StartDate__c <= :today AND SBQQ__EndDate__c >= :today' +
                ' AND SBQQ__TerminatedDate__c = null AND SBQQ__Bundled__c = false' +
                ((officeId != null) ? ' AND SBQQ__Account__c = :officeId' : '') + ' GROUP BY CurrencyIsoCode')) {
            subCnt += (Integer) ar.get('sc');
            subVal += CurrencyConvUSD.toUSD((Decimal) ar.get('sv'), (String) ar.get('iso'), today);
        }
        out.activeSubs = subCnt;
        out.activeSubValue = subVal.setScale(2);
        out.groups = groupsLive(firmId, period, businessType, officeId);            // group panel: office filter
        out.offices = getOfficeBreakdown(firmId, period, businessType, commercialGroup); // office panel: group filter

        // headline ACV (line-grain) for the selected period: the chosen group's ACV when a group is
        // filtered, else Σ of all groups' ACV (for the active office/business). Other periods' acv
        // stay null — the LWC re-queries per period and only renders the selected period.
        Decimal acvSel = 0;
        for (GroupDTO g : out.groups) {
            if (String.isBlank(commercialGroup) || g.name == commercialGroup) acvSel += (g.acv == null ? 0 : g.acv);
        }
        for (PeriodDTO p : out.periods) if (p.key == period) p.acv = acvSel.setScale(2);
        return out;
    }

    /** Live group breakdown for one period, optionally filtered to one office. */
    static List<GroupDTO> groupsLive(Id firmId, String period, String businessType, Id officeId) {
        PeriodBounds b = boundsFor(period);
        Date startD = b.startDate, endD = b.endDate;
        List<String> renewalTypes = RENEWAL_TYPES;
        String dateClause = b.unbounded ? '' : ' AND Opportunity.CloseDate >= :startD AND Opportunity.CloseDate <= :endD';
        String officeClause = (officeId != null) ? ' AND Opportunity.AccountId = :officeId' : '';
        String soql =
            'SELECT Product2.Family fam, Product2.Product_Type__c pt, CurrencyIsoCode iso, Opportunity.StageName st, ' +
            'CALENDAR_YEAR(Opportunity.CloseDate) yr, SUM(TotalPrice) v, SUM(Annual_Contract_Value__c) acv, COUNT(Id) items FROM OpportunityLineItem ' +
            'WHERE Opportunity.Ultimate_Account__c = :firmId AND Opportunity.StageName IN (:WON, :CANC)' +
            dateClause + officeClause + businessClause(businessType, 'Opportunity.') +
            ' GROUP BY Product2.Family, Product2.Product_Type__c, CurrencyIsoCode, Opportunity.StageName, CALENDAR_YEAR(Opportunity.CloseDate)';
        Map<String, GroupDTO> acc = new Map<String, GroupDTO>();
        for (AggregateResult ar : Database.query(soql)) {
            String grp = FirmRollupService.resolveGroup((String) ar.get('fam'), (String) ar.get('pt'));
            Integer yr = (Integer) ar.get('yr');
            Date asOf = (yr == null) ? Date.today() : Date.newInstance(yr, 7, 1);
            Decimal usd = CurrencyConvUSD.toUSD((Decimal) ar.get('v'), (String) ar.get('iso'), asOf);
            Decimal acvUsd = CurrencyConvUSD.toUSD((Decimal) ar.get('acv'), (String) ar.get('iso'), asOf);
            if (CANC.equals((String) ar.get('st'))) { if (usd > 0) usd = -usd; if (acvUsd > 0) acvUsd = -acvUsd; }
            GroupDTO g = acc.get(grp);
            if (g == null) { g = new GroupDTO(); g.name = grp; g.value = 0; g.items = 0; g.acv = 0; acc.put(grp, g); }
            g.value += usd; g.items += (Integer) ar.get('items'); g.acv += acvUsd;
        }
        List<GroupDTO> out = new List<GroupDTO>();
        for (GroupDTO g : acc.values()) {
            if (g.value != 0 || g.items != 0 || g.acv != 0) { g.value = g.value.setScale(2); g.acv = g.acv.setScale(2); out.add(g); }
        }
        return out;
    }

    /** Opportunity-level commercial-group semi-join clause; populates the bind lists (nef/ept). */
    static String oppGroupFilter(String commercialGroup, List<String> nef, List<String> ept, Boolean[] inclOther) {
        if (String.isBlank(commercialGroup)) return '';
        for (Product_Family_Group__mdt m : Product_Family_Group__mdt.getAll().values()) {
            if (m.Commercial_Group__c != commercialGroup) continue;
            if ('Events'.equals(m.Family__c)) {
                if (String.isBlank(m.Product_Type_1__c)) inclOther[0] = true; else ept.add(m.Product_Type_1__c);
            } else {
                nef.add(m.Family__c);
            }
        }
        List<String> ors = new List<String>();
        if (!nef.isEmpty()) ors.add('Product2.Family IN :nef');
        if (!ept.isEmpty()) ors.add('(Product2.Family = \'Events\' AND Product2.Product_Type__c IN :ept)');
        if (inclOther[0]) ors.add('(Product2.Family = \'Events\' AND (Product2.Product_Type__c = null OR (Product2.Product_Type__c != \'Sponsorship\' AND Product2.Product_Type__c != \'Ticket\')))');
        String sub = ors.isEmpty() ? 'SELECT OpportunityId FROM OpportunityLineItem WHERE Id = null'
                                   : 'SELECT OpportunityId FROM OpportunityLineItem WHERE ' + String.join(ors, ' OR ');
        return ' AND Id IN (' + sub + ')';
    }

    // ---------- office breakdown (live) ----------
    @AuraEnabled
    public static List<OfficeDTO> getOfficeBreakdown(Id firmId, String period, String businessType) {
        return getOfficeBreakdown(firmId, period, businessType, null);
    }
    /** Office breakdown, optionally filtered to one commercial group (opp-grain semi-join). */
    public static List<OfficeDTO> getOfficeBreakdown(Id firmId, String period, String businessType, String commercialGroup) {
        PeriodBounds b = boundsFor(period);
        Date startD = b.startDate, endD = b.endDate, today = Date.today();
        List<String> renewalTypes = RENEWAL_TYPES;
        List<String> nef = new List<String>(); List<String> ept = new List<String>(); Boolean[] inclOther = new Boolean[]{ false };
        String groupClause = oppGroupFilter(commercialGroup, nef, ept, inclOther);
        Boolean groupFiltered = String.isNotBlank(commercialGroup);
        Map<Id, OfficeDTO> byOffice = new Map<Id, OfficeDTO>();

        String dateClause = b.unbounded ? '' : ' AND CloseDate >= :startD AND CloseDate <= :endD';
        String soql =
            'SELECT AccountId off, CurrencyIsoCode iso, StageName st, ' +
            'CALENDAR_YEAR(CloseDate) yr, CALENDAR_MONTH(CloseDate) mo, SUM(Amount) v, COUNT(Id) c ' +
            'FROM Opportunity WHERE Ultimate_Account__c = :firmId AND StageName IN (:WON, :CANC)' + dateClause + groupClause +
            businessClause(businessType) +
            ' GROUP BY AccountId, CurrencyIsoCode, StageName, CALENDAR_YEAR(CloseDate), CALENDAR_MONTH(CloseDate)';
        for (AggregateResult ar : Database.query(soql)) {
            Id off = (Id) ar.get('off');
            if (off == null) continue;
            OfficeDTO o = office(byOffice, off);
            Integer yr = (Integer) ar.get('yr');
            Integer mo = (Integer) ar.get('mo');
            Date asOf = (yr == null) ? today : Date.newInstance(yr, (mo == null ? 1 : mo), 1);
            Decimal usd = CurrencyConvUSD.toUSD((Decimal) ar.get('v'), (String) ar.get('iso'), asOf);
            o.value += usd;
            if (WON.equals((String) ar.get('st'))) o.wonCount += (Integer) ar.get('c');
        }
        // active subs per office
        for (AggregateResult ar : [
                SELECT SBQQ__Account__c off, COUNT(Id) c
                FROM SBQQ__Subscription__c
                WHERE Ultimate_Parent__c = :firmId
                  AND SBQQ__StartDate__c <= :today AND SBQQ__EndDate__c >= :today
                  AND SBQQ__TerminatedDate__c = null AND SBQQ__Bundled__c = false
                GROUP BY SBQQ__Account__c]) {
            Id off = (Id) ar.get('off');
            if (off == null) continue;
            // when group-filtered, only annotate offices that already have group activity
            if (groupFiltered && !byOffice.containsKey(off)) continue;
            office(byOffice, off).subs += (Integer) ar.get('c');
        }
        // resolve names + location
        Set<Id> offIds = byOffice.keySet();
        for (Account a : [SELECT Id, Name, BillingCity, BillingCountry FROM Account WHERE Id IN :offIds]) {
            OfficeDTO o = byOffice.get(a.Id);
            o.officeName = a.Name;
            o.city = a.BillingCity;
            o.country = a.BillingCountry;
        }
        List<OfficeDTO> out = byOffice.values();
        out.sort();
        return out;
    }

    // ---------- opportunity drill (live, paginated) ----------
    @AuraEnabled
    public static OppPageDTO getOpportunities(Id firmId, Id officeId, String commercialGroup,
                                              String period, String businessType,
                                              Integer pageSize, Integer offset) {
        Integer lim = (pageSize == null || pageSize <= 0) ? 10 : Math.min(pageSize, 200);
        Integer off = (offset == null || offset < 0) ? 0 : Math.min(offset, 2000); // SOQL OFFSET cap
        PeriodBounds b = boundsFor(period);
        Date startD = b.startDate, endD = b.endDate;
        List<String> renewalTypes = RENEWAL_TYPES;

        String whereClause = 'Ultimate_Account__c = :firmId AND StageName IN (:WON, :CANC)';
        if (officeId != null) whereClause += ' AND AccountId = :officeId';
        if (!b.unbounded) whereClause += ' AND CloseDate >= :startD AND CloseDate <= :endD';
        whereClause += businessClause(businessType);

        // group filter via CMDT-resolved family/Product-Type-1 semi-join on line items
        List<String> nonEventFamilies = new List<String>();
        List<String> eventPtypes = new List<String>();
        Boolean inclEventsOther = false;
        if (String.isNotBlank(commercialGroup)) {
            for (Product_Family_Group__mdt m : Product_Family_Group__mdt.getAll().values()) {
                if (m.Commercial_Group__c != commercialGroup) continue;
                if ('Events'.equals(m.Family__c)) {
                    if (String.isBlank(m.Product_Type_1__c)) inclEventsOther = true;
                    else eventPtypes.add(m.Product_Type_1__c);
                } else {
                    nonEventFamilies.add(m.Family__c);
                }
            }
            List<String> ors = new List<String>();
            if (!nonEventFamilies.isEmpty()) ors.add('Product2.Family IN :nonEventFamilies');
            if (!eventPtypes.isEmpty()) ors.add('(Product2.Family = \'Events\' AND Product2.Product_Type__c IN :eventPtypes)');
            if (inclEventsOther) ors.add('(Product2.Family = \'Events\' AND (Product2.Product_Type__c = null OR (Product2.Product_Type__c != \'Sponsorship\' AND Product2.Product_Type__c != \'Ticket\')))');
            String sub = ors.isEmpty() ? 'SELECT OpportunityId FROM OpportunityLineItem WHERE Id = null'
                                       : 'SELECT OpportunityId FROM OpportunityLineItem WHERE ' + String.join(ors, ' OR ');
            whereClause += ' AND Id IN (' + sub + ')';
        }

        OppPageDTO page = new OppPageDTO();
        page.total = Database.countQuery('SELECT COUNT() FROM Opportunity WHERE ' + whereClause);
        page.pageSize = lim;
        page.offset = off;
        page.rows = new List<OppDTO>();

        String q = 'SELECT Id, Name, Account.Name, CloseDate, Type, StageName, Amount, CurrencyIsoCode ' +
                   'FROM Opportunity WHERE ' + whereClause +
                   ' ORDER BY CloseDate DESC, Id DESC LIMIT :lim OFFSET :off';
        for (Opportunity o : Database.query(q)) {
            OppDTO d = new OppDTO();
            d.id = o.Id;
            d.name = o.Name;
            d.officeName = (o.Account != null) ? o.Account.Name : null;
            d.closeDate = o.CloseDate;
            d.type = o.Type;
            d.stage = o.StageName;
            d.amountUSD = CurrencyConvUSD.toUSD(o.Amount, o.CurrencyIsoCode, o.CloseDate);
            page.rows.add(d);
        }
        return page;
    }

    // ---------- refresh ----------
    @AuraEnabled
    public static void refreshFirm(Id firmId) {
        if (firmId == null) return;
        OpportunityFirmRollupHelper.enqueue(new Set<Id>{ firmId });
    }

    // ---------- period bounds ----------
    class PeriodBounds { Date startDate; Date endDate; Boolean unbounded = false; }

    static PeriodBounds boundsFor(String period) {
        if (fyStartMonth == null) {
            fyStartMonth = [SELECT FiscalYearStartMonth FROM Organization LIMIT 1].FiscalYearStartMonth;
        }
        Date today = Date.today();
        PeriodBounds b = new PeriodBounds();
        Date cfyStart = fyStart(today);
        if ('cfy'.equalsIgnoreCase(period)) {
            b.startDate = cfyStart; b.endDate = cfyStart.addYears(1).addDays(-1);
        } else if ('pfy'.equalsIgnoreCase(period)) {
            b.startDate = cfyStart.addYears(-1); b.endDate = cfyStart.addDays(-1);
        } else if ('t12m'.equalsIgnoreCase(period)) {
            b.startDate = today.addMonths(-12); b.endDate = today;
        } else {
            b.unbounded = true;
        }
        return b;
    }
    static Date fyStart(Date today) {
        Integer y = today.year();
        if (today.month() < fyStartMonth) y--;
        return Date.newInstance(y, fyStartMonth, 1);
    }

    // ---------- helpers ----------
    static Integer nz(Decimal d) { return (d == null) ? 0 : d.intValue(); }
    static Decimal nzd(Decimal d) { return (d == null) ? 0 : d; }
    static PeriodDTO period(String key, String label, Decimal v, Decimal won) {
        PeriodDTO p = new PeriodDTO();
        p.key = key; p.label = label; p.netValue = nzd(v); p.wonCount = nz(won);
        return p;
    }
    static OfficeDTO office(Map<Id, OfficeDTO> m, Id off) {
        OfficeDTO o = m.get(off);
        if (o == null) { o = new OfficeDTO(); o.officeId = off; m.put(off, o); }
        return o;
    }

    // ---------- DTOs ----------
    public class SummaryDTO {
        @AuraEnabled public Id firmId;
        @AuraEnabled public String firmName;
        @AuraEnabled public String targetCurrency;
        @AuraEnabled public String fxBasis;
        @AuraEnabled public Datetime lastRefreshed;
        @AuraEnabled public Integer activeSubs;
        @AuraEnabled public Decimal activeSubValue;
        @AuraEnabled public Integer cancelCount;
        @AuraEnabled public Decimal cancelValue;
        @AuraEnabled public List<PeriodDTO> periods;
    }
    public class PeriodDTO {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public Decimal netValue;
        @AuraEnabled public Integer wonCount;
        @AuraEnabled public Decimal acv;       // net Won ACV (USD) for the period
    }
    public class GroupDTO {
        @AuraEnabled public String name;
        @AuraEnabled public Decimal allTimeValue; @AuraEnabled public Integer allTimeItems; @AuraEnabled public Decimal allTimeAcv;
        @AuraEnabled public Decimal cfyValue;     @AuraEnabled public Integer cfyItems;     @AuraEnabled public Decimal cfyAcv;
        @AuraEnabled public Decimal pfyValue;     @AuraEnabled public Integer pfyItems;     @AuraEnabled public Decimal pfyAcv;
        @AuraEnabled public Decimal t12mValue;    @AuraEnabled public Integer t12mItems;    @AuraEnabled public Decimal t12mAcv;
        // flat, period-resolved value/items/acv — populated by the live cross-filter path only
        @AuraEnabled public Decimal value;        @AuraEnabled public Integer items;        @AuraEnabled public Decimal acv;
    }
    public class ViewDTO {
        @AuraEnabled public List<PeriodDTO> periods;
        @AuraEnabled public Decimal cancelValue;
        @AuraEnabled public Integer cancelCount;
        @AuraEnabled public Integer activeSubs;
        @AuraEnabled public Decimal activeSubValue;
        @AuraEnabled public List<GroupDTO> groups;
        @AuraEnabled public List<OfficeDTO> offices;
    }
    public class OfficeDTO implements Comparable {
        @AuraEnabled public Id officeId;
        @AuraEnabled public String officeName;
        @AuraEnabled public String city;
        @AuraEnabled public String country;
        @AuraEnabled public Decimal value = 0;
        @AuraEnabled public Integer wonCount = 0;
        @AuraEnabled public Integer subs = 0;
        public Integer compareTo(Object o) {
            OfficeDTO other = (OfficeDTO) o;
            if (value == other.value) return 0;
            return (value > other.value) ? -1 : 1; // value desc
        }
    }
    public class OppPageDTO {
        @AuraEnabled public Integer total;
        @AuraEnabled public Integer pageSize;
        @AuraEnabled public Integer offset;
        @AuraEnabled public List<OppDTO> rows;
    }
    public class OppDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String officeName;
        @AuraEnabled public Date closeDate;
        @AuraEnabled public String type;
        @AuraEnabled public String stage;
        @AuraEnabled public Decimal amountUSD;
    }
}
