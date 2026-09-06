import { LightningElement, api } from 'lwc';

/**
 * REV-69 — X (eXisting Process) station. Presentational.
 * Four driver cards (multi-select); "Other" reveals a free-text note (UX only —
 * there is no notes field to persist it). Answered when >= 1 driver is selected.
 * The four values mirror the restricted picklist on
 * Opportunity.LexPRO_Qual_Process_Improvement__c.
 * Emits resolve {field:'X', values:[...]}.
 */
const DRIVERS = [
    { value: 'Help keep up with the influx of regulatory change', label: 'Keep up with the influx of regulatory change' },
    { value: 'Providing a reliable source of data', label: 'Provide a reliable source of data' },
    { value: 'Reducing Cost of External Counsel', label: 'Reduce cost of external counsel' },
    { value: 'Other', label: 'Other' }
];

export default class LexproStationProcess extends LightningElement {
    _values = [];
    _otherText = '';
    _otherSeeded = false;

    @api
    get values() {
        return this._values;
    }
    set values(val) {
        this._values = Array.isArray(val) ? [...val] : [];
    }

    @api
    get otherText() {
        return this._otherText;
    }
    set otherText(val) {
        // One-time seed from the saved record.
        if (!this._otherSeeded && val) {
            this._otherText = val;
            this._otherSeeded = true;
        }
    }

    get drivers() {
        return DRIVERS.map((d) => {
            const isSel = this._values.includes(d.value);
            return {
                value: d.value,
                label: d.label,
                pressed: isSel ? 'true' : 'false',
                cls: isSel ? 'lex-card lex-card_on' : 'lex-card'
            };
        });
    }

    get showOther() {
        return this._values.includes('Other');
    }

    get answered() {
        return this._values.length > 0;
    }

    toggle(event) {
        const v = event.currentTarget.dataset.val;
        if (this._values.includes(v)) {
            this._values = this._values.filter((x) => x !== v);
        } else {
            this._values = [...this._values, v];
        }
        this.emit();
    }

    handleOther(event) {
        this._otherText = event.target.value;
        this.emit();
    }

    emit() {
        this.dispatchEvent(
            new CustomEvent('resolve', {
                detail: {
                    field: 'X',
                    values: this._values,
                    other: this._values.includes('Other') ? this._otherText : ''
                }
            })
        );
    }
}
