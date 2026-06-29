/**
 * FSS §7 — LWC read controller. with sharing; FLS/CRUD enforced on record reads.
 * Headline + group reads come from PERSISTED rollups (instant, cacheable). Office and opportunity
 * drill-downs are computed LIVE (imperative); every money figure is converted to USD via
 * CurrencyConvUSD so it renders USD regardless of the running user's currency.
 */
public with sharing class FirmSalesSummaryController {

    static final String WON = FirmRollupService.STAGE_WON;
    static final String CANC = FirmRollupService.STAGE_CANC;
    static Integer fyStartMonth;

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
        return s;
    }

    // ---------- groups (persisted, cacheable) ----------
    @AuraEnabled(cacheable=true)
    public static List<GroupDTO> getGroupBreakdown(Id firmId) {
        List<GroupDTO> out = new List<GroupDTO>();
        for (Firm_Product_Group_Rollup_USD__c r : [
                SELECT Commercial_Group__c,
                       Won_Value_AllTime_USD__c, Won_Items_AllTime__c,
                       Won_Value_CFY_USD__c, Won_Items_CFY__c,
                       Won_Value_PFY_USD__c, Won_Items_PFY__c,
                       Won_Value_T12M_USD__c, Won_Items_T12M__c
                FROM Firm_Product_Group_Rollup_USD__c
                WHERE Firm__c = :firmId WITH SECURITY_ENFORCED
                ORDER BY Won_Value_AllTime_USD__c DESC NULLS LAST]) {
            GroupDTO g = new GroupDTO();
            g.name = r.Commercial_Group__c;
            g.allTimeValue = nzd(r.Won_Value_AllTime_USD__c); g.allTimeItems = nz(r.Won_Items_AllTime__c);
            g.cfyValue = nzd(r.Won_Value_CFY_USD__c);         g.cfyItems = nz(r.Won_Items_CFY__c);
            g.pfyValue = nzd(r.Won_Value_PFY_USD__c);         g.pfyItems = nz(r.Won_Items_PFY__c);
            g.t12mValue = nzd(r.Won_Value_T12M_USD__c);       g.t12mItems = nz(r.Won_Items_T12M__c);
            out.add(g);
        }
        return out;
    }

    // ---------- office breakdown (live) ----------
    @AuraEnabled
    public static List<OfficeDTO> getOfficeBreakdown(Id firmId, String period) {
        PeriodBounds b = boundsFor(period);
        Date startD = b.startDate, endD = b.endDate, today = Date.today();
        Map<Id, OfficeDTO> byOffice = new Map<Id, OfficeDTO>();

        String dateClause = b.unbounded ? '' : ' AND CloseDate >= :startD AND CloseDate <= :endD';
        String soql =
            'SELECT AccountId off, CurrencyIsoCode iso, StageName st, ' +
            'CALENDAR_YEAR(CloseDate) yr, CALENDAR_MONTH(CloseDate) mo, SUM(Amount) v, COUNT(Id) c ' +
            'FROM Opportunity WHERE Ultimate_Account__c = :firmId AND StageName IN (:WON, :CANC)' + dateClause +
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
                GROUP BY SBQQ__Account__c]) {
            Id off = (Id) ar.get('off');
            if (off == null) continue;
            office(byOffice, off).subs += (Integer) ar.get('c');
        }
        // resolve names
        Set<Id> offIds = byOffice.keySet();
        for (Account a : [SELECT Id, Name FROM Account WHERE Id IN :offIds]) {
            byOffice.get(a.Id).officeName = a.Name;
        }
        List<OfficeDTO> out = byOffice.values();
        out.sort();
        return out;
    }

    // ---------- opportunity drill (live, paginated) ----------
    @AuraEnabled
    public static OppPageDTO getOpportunities(Id firmId, Id officeId, String commercialGroup,
                                              String period, Integer pageSize, Integer offset) {
        Integer lim = (pageSize == null || pageSize <= 0) ? 10 : Math.min(pageSize, 200);
        Integer off = (offset == null || offset < 0) ? 0 : Math.min(offset, 2000); // SOQL OFFSET cap
        PeriodBounds b = boundsFor(period);
        Date startD = b.startDate, endD = b.endDate;

        String whereClause = 'Ultimate_Account__c = :firmId AND StageName IN (:WON, :CANC)';
        if (officeId != null) whereClause += ' AND AccountId = :officeId';
        if (!b.unbounded) whereClause += ' AND CloseDate >= :startD AND CloseDate <= :endD';

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
    }
    public class GroupDTO {
        @AuraEnabled public String name;
        @AuraEnabled public Decimal allTimeValue; @AuraEnabled public Integer allTimeItems;
        @AuraEnabled public Decimal cfyValue;     @AuraEnabled public Integer cfyItems;
        @AuraEnabled public Decimal pfyValue;     @AuraEnabled public Integer pfyItems;
        @AuraEnabled public Decimal t12mValue;    @AuraEnabled public Integer t12mItems;
    }
    public class OfficeDTO implements Comparable {
        @AuraEnabled public Id officeId;
        @AuraEnabled public String officeName;
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
