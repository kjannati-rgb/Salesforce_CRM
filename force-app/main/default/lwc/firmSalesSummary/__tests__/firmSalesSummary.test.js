import { createElement } from 'lwc';
import FirmSalesSummary from 'c/firmSalesSummary';
import getSummary from '@salesforce/apex/FirmSalesSummaryController.getSummary';
import getGroupBreakdown from '@salesforce/apex/FirmSalesSummaryController.getGroupBreakdown';
import getOfficeBreakdown from '@salesforce/apex/FirmSalesSummaryController.getOfficeBreakdown';

// imperative apex mocks
jest.mock(
    '@salesforce/apex/FirmSalesSummaryController.getOfficeBreakdown',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/FirmSalesSummaryController.getOpportunities',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/FirmSalesSummaryController.refreshFirm',
    () => ({ default: jest.fn(() => Promise.resolve()) }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/FirmSalesSummaryController.getBusinessView',
    () => ({ default: jest.fn(() => Promise.resolve({ periods: [], cancelValue: 0, cancelCount: 0, groups: [] })) }),
    { virtual: true }
);

const SUMMARY = {
    firmId: '001x', firmName: 'Sterling Hartwell LLP', targetCurrency: 'USD', fxBasis: 'Dated',
    lastRefreshed: '2026-06-29T00:00:00.000Z', activeSubs: 96, activeSubValue: 1340000,
    cancelCount: 37, cancelValue: -214000,
    periods: [
        { key: 'alltime', label: 'All-time', netValue: 4820000, wonCount: 1284 },
        { key: 'cfy', label: 'This FY', netValue: 910000, wonCount: 247 },
        { key: 'pfy', label: 'Last FY', netValue: 1120000, wonCount: 298 },
        { key: 't12m', label: 'Last 12 mo', netValue: 1050000, wonCount: 271 }
    ]
};
const GROUPS = [
    { name: 'Law.com / ALM', allTimeValue: 1080000, allTimeItems: 410, cfyValue: 224000, cfyItems: 80, pfyValue: 0, pfyItems: 0, t12mValue: 0, t12mItems: 0 },
    { name: 'Events - Sponsorship', allTimeValue: 780000, allTimeItems: 102, cfyValue: 160000, cfyItems: 20, pfyValue: 0, pfyItems: 0, t12mValue: 0, t12mItems: 0 }
];

function flush() { return Promise.resolve(); }

describe('c-firm-sales-summary', () => {
    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
        jest.clearAllMocks();
    });

    function mount() {
        getOfficeBreakdown.mockResolvedValue([
            { officeId: '001o1', officeName: 'London', value: 1700000, wonCount: 472, subs: 38 }
        ]);
        const el = createElement('c-firm-sales-summary', { is: FirmSalesSummary });
        el.recordId = '001x';
        document.body.appendChild(el);
        return el;
    }

    it('formats KPIs in USD from persisted summary', async () => {
        const el = mount();
        getSummary.emit(SUMMARY);
        getGroupBreakdown.emit(GROUPS);
        await flush();
        const kpiVals = el.shadowRoot.querySelectorAll('.k-val');
        expect(kpiVals.length).toBe(4);
        expect(kpiVals[0].textContent).toBe('$4.82M');   // net won value, all-time
        expect(kpiVals[1].textContent).toBe('1,284');     // won count
    });

    it('reacts to the period toggle', async () => {
        const el = mount();
        getSummary.emit(SUMMARY);
        getGroupBreakdown.emit(GROUPS);
        await flush();
        const cfyBtn = el.shadowRoot.querySelector('button[data-key="cfy"]');
        cfyBtn.click();
        await flush();
        const netVal = el.shadowRoot.querySelector('.k-val');
        expect(netVal.textContent).toBe('$910K');
    });

    it('renders persisted commercial-group rows sorted by value', async () => {
        const el = mount();
        getSummary.emit(SUMMARY);
        getGroupBreakdown.emit(GROUPS);
        await flush();
        const names = [...el.shadowRoot.querySelectorAll('.grp-name')].map((n) => n.textContent);
        expect(names).toContain('Law.com / ALM');
        expect(names).toContain('Events - Sponsorship');
    });
});
