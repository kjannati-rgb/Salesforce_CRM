import { createElement } from 'lwc';
import PfcQualityCard from 'c/pfcQualityCard';
import getCardData from '@salesforce/apex/PFCQualityCardController.getCardData';

jest.mock(
    '@salesforce/apex/PFCQualityCardController.getCardData',
    () => {
        const {
            createApexTestWireAdapter
        } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);

const LEAD_SCORED = {
    mode: 'lead',
    fitScore: 83,
    scoreReasoning: 'Senior in-house counsel; strong ICP match.',
    clayRouted: true,
    pfcSource: 'Inbound Form',
    email: 'paul@openai.com',
    domainName: 'openai.com',
    domainClass: 'corporate',
    duplicates: [],
    firm: null
};

const LEAD_PENDING = {
    ...LEAD_SCORED,
    fitScore: null,
    scoreReasoning: null,
    clayRouted: false,
    domainName: 'gmail.com',
    domainClass: 'freemail',
    duplicates: [
        {
            recordId: 'a5E000000000001AAA',
            name: 'Dup 1',
            formName: 'PRO — Content Download',
            stage: 'New',
            createdDate: '2026-05-14T09:00:00.000Z'
        },
        {
            recordId: 'a5E000000000002AAA',
            name: 'Dup 2',
            formName: 'PRO — Scanner',
            stage: 'Working',
            createdDate: '2026-04-02T09:00:00.000Z'
        }
    ]
};

const CONTACT_OVERLAP = {
    mode: 'contact',
    fitScore: null,
    scoreReasoning: null,
    clayRouted: false,
    pfcSource: 'Inbound Form',
    email: 'cyril@cliffordchance.com',
    domainName: 'cliffordchance.com',
    domainClass: 'corporate',
    duplicates: [],
    firm: {
        firmId: '001000000000001AAA',
        firmName: 'Clifford Chance LLP',
        officeName: 'Clifford Chance LLP (Paris)',
        activeSubs: 36,
        familyCount: 7,
        families: [
            { family: 'Subs - Specialist Platforms', count: 21 },
            { family: 'Subs - Lexology Pro', count: 3 }
        ],
        existingCustomer: true,
        requestedBrand: 'IAM',
        requestedFamily: 'Subs - Specialist Platforms',
        requestedBrandFamilyOverlap: true
    }
};

const CONTACT_NO_SUBS = {
    ...CONTACT_OVERLAP,
    firm: {
        ...CONTACT_OVERLAP.firm,
        activeSubs: 0,
        familyCount: 0,
        families: [],
        existingCustomer: false,
        requestedBrandFamilyOverlap: false
    }
};

async function mount(payload) {
    const el = createElement('c-pfc-quality-card', { is: PfcQualityCard });
    el.recordId = 'a5E000000000000AAA';
    document.body.appendChild(el);
    getCardData.emit(payload);
    await Promise.resolve();
    return el;
}

describe('c-pfc-quality-card', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('lead mode renders score, corporate badge and reasoning', async () => {
        const el = await mount(LEAD_SCORED);
        expect(el.shadowRoot.querySelector('h2').textContent).toBe('Lead Quality');
        expect(
            el.shadowRoot.querySelector('[data-id="score"]').textContent
        ).toBe('83');
        expect(
            el.shadowRoot.querySelector('[data-id="domain-badge"]').textContent
        ).toContain('Corporate domain · openai.com');
        expect(el.shadowRoot.querySelector('[data-id="pending"]')).toBeNull();
        expect(el.shadowRoot.querySelector('[data-id="dupes"]')).toBeNull();
    });

    it('lead mode empty state: pending score, freemail warning, duplicate list', async () => {
        const el = await mount(LEAD_PENDING);
        expect(
            el.shadowRoot.querySelector('[data-id="score"]').textContent
        ).toBe('—');
        expect(
            el.shadowRoot.querySelector('[data-id="pending"]').textContent
        ).toContain('Score pending');
        expect(
            el.shadowRoot.querySelector('[data-id="domain-badge"]').textContent
        ).toContain('Free-mail address · gmail.com');
        const dupes = el.shadowRoot.querySelector('[data-id="dupes"]');
        expect(dupes.textContent).toContain('2 other completions');
        expect(dupes.querySelectorAll('a').length).toBe(2);
        expect(dupes.querySelector('a').getAttribute('href')).toBe(
            '/a5E000000000001AAA'
        );
    });

    it('contact mode renders account context with entitlement flag', async () => {
        const el = await mount(CONTACT_OVERLAP);
        expect(el.shadowRoot.querySelector('h2').textContent).toBe(
            'Account Context'
        );
        expect(
            el.shadowRoot.querySelector('[data-id="subcount"]').textContent
        ).toBe('36');
        expect(
            el.shadowRoot.querySelector('[data-id="customer-badge"]')
        ).not.toBeNull();
        const flag = el.shadowRoot.querySelector('[data-id="entitlement"]');
        expect(flag.textContent).toContain('prospect requested IAM');
        expect(flag.textContent).toContain('route to CSM');
    });

    it('contact mode without any account renders guidance instead of crashing', async () => {
        const el = await mount({ ...CONTACT_OVERLAP, firm: null });
        expect(
            el.shadowRoot.querySelector('[data-id="no-account"]').textContent
        ).toContain("isn't linked to an account");
        expect(el.shadowRoot.querySelector('[data-id="subcount"]')).toBeNull();
        expect(el.shadowRoot.querySelector('[data-id="entitlement"]')).toBeNull();
    });

    it('contact mode empty state: no subs, no entitlement flag', async () => {
        const el = await mount(CONTACT_NO_SUBS);
        expect(
            el.shadowRoot.querySelector('[data-id="no-subs"]').textContent
        ).toContain('No active firm-level subscriptions');
        expect(el.shadowRoot.querySelector('[data-id="entitlement"]')).toBeNull();
        expect(
            el.shadowRoot.querySelector('[data-id="customer-badge"]')
        ).toBeNull();
    });
});
