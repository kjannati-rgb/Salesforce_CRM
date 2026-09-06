import { LightningElement, api } from 'lwc';

/**
 * REV-69 — E (Essential Work Areas) station. Presentational.
 * Renders work areas grouped by tier (Core = blue/strong, Beyond = amber/confirm)
 * plus an "Other" escape hatch with free text, and resolves the Content Yes/No
 * answer. Selecting >= 1 listed area auto-suggests "Yes" ("Other" alone does not,
 * since it's an area we don't list). Never auto-flips to No.
 * Emits resolve {field:'E', value, areas:[...labels incl 'Other'], other:text}.
 */
export default class LexproStationContent extends LightningElement {
    _workAreas = [];
    _value;
    _manual = false;
    selected = {};
    otherSelected = false;
    _otherText = '';

    _selectedAreas = [];
    _seededSel = false;
    _otherSeeded = false;

    @api
    get workAreas() {
        return this._workAreas;
    }
    set workAreas(val) {
        this._workAreas = Array.isArray(val) ? val : [];
        this.trySeed();
    }

    @api
    get value() {
        return this._value;
    }
    set value(val) {
        if (val) {
            this._value = val;
            this._manual = true;
        }
    }

    @api
    get selectedAreas() {
        return this._selectedAreas;
    }
    set selectedAreas(val) {
        this._selectedAreas = Array.isArray(val) ? val : [];
        this.trySeed();
    }

    @api
    get otherText() {
        return this._otherText;
    }
    set otherText(val) {
        // One-time seed from the saved record.
        if (!this._otherSeeded && val) {
            this._otherText = val;
            this.otherSelected = true;
            this._otherSeeded = true;
        }
    }

    // One-time: reflect previously-saved work-area labels back onto the chips.
    trySeed() {
        if (this._seededSel || !this._workAreas.length || !this._selectedAreas.length) return;
        const byLabel = {};
        this._workAreas.forEach((w) => {
            byLabel[w.MasterLabel] = w.DeveloperName;
        });
        const sel = {};
        this._selectedAreas.forEach((lbl) => {
            if (lbl === 'Other') {
                this.otherSelected = true;
            } else {
                const dn = byLabel[lbl];
                if (dn) sel[dn] = true;
            }
        });
        this.selected = sel;
        this._seededSel = true;
    }

    get coreAreas() {
        return this.decorate(this._workAreas.filter((w) => w.Tier__c === 'Core'));
    }
    get beyondAreas() {
        return this.decorate(this._workAreas.filter((w) => w.Tier__c === 'Beyond'));
    }
    get hasBeyond() {
        return this._workAreas.some((w) => w.Tier__c === 'Beyond');
    }

    decorate(list) {
        return list.map((w) => {
            const isSel = !!this.selected[w.DeveloperName];
            let cls = w.Tier__c === 'Core' ? 'lex-chip lex-chip_core' : 'lex-chip lex-chip_beyond';
            if (isSel) cls += ' lex-chip_on';
            return {
                key: w.DeveloperName,
                label: w.MasterLabel,
                pressed: isSel ? 'true' : 'false',
                cls
            };
        });
    }

    get otherClass() {
        return this.otherSelected ? 'lex-chip lex-chip_other lex-chip_on' : 'lex-chip lex-chip_other';
    }
    get otherPressed() {
        return this.otherSelected ? 'true' : 'false';
    }
    get showOther() {
        return this.otherSelected;
    }

    get answered() {
        return !!this._value;
    }
    get pickerDisabled() {
        // Once "No" is chosen there are no relevant work areas — lock the picker.
        return this._value === 'No';
    }
    get yesClass() {
        return this._value === 'Yes' ? 'lex-seg lex-seg_on' : 'lex-seg';
    }
    get noClass() {
        return this._value === 'No' ? 'lex-seg lex-seg_on' : 'lex-seg';
    }
    get yesPressed() {
        return this._value === 'Yes' ? 'true' : 'false';
    }
    get noPressed() {
        return this._value === 'No' ? 'true' : 'false';
    }

    toggle(event) {
        const key = event.currentTarget.dataset.key;
        this.selected = { ...this.selected, [key]: !this.selected[key] };
        this._manual = false;
        this.autoDerive();
        this.emit();
    }

    toggleOther() {
        this.otherSelected = !this.otherSelected;
        this.emit();
    }

    handleOther(event) {
        this._otherText = event.target.value;
        this.emit();
    }

    autoDerive() {
        // Selecting any listed work area suggests Yes; "Other" alone does not.
        // Never auto-flip to No — the rep chooses No explicitly.
        const anyListed = Object.keys(this.selected).some((k) => this.selected[k]);
        if (anyListed) this._value = 'Yes';
    }

    pick(event) {
        this._value = event.currentTarget.dataset.val;
        this._manual = true;
        if (this._value === 'No') {
            this.selected = {};
            this.otherSelected = false;
            this._otherText = '';
        }
        this.emit();
    }

    selectedLabels() {
        const labels = this._workAreas
            .filter((w) => this.selected[w.DeveloperName])
            .map((w) => w.MasterLabel);
        if (this.otherSelected) labels.push('Other');
        return labels;
    }

    emit() {
        this.dispatchEvent(
            new CustomEvent('resolve', {
                detail: {
                    field: 'E',
                    value: this._value,
                    areas: this.selectedLabels(),
                    other: this.otherSelected ? this._otherText : ''
                }
            })
        );
    }
}
