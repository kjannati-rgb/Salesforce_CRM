import { LightningElement, api } from 'lwc';

/**
 * REV-69 — L (Locations) station. Presentational.
 * Renders the coverage map from config and resolves the Jurisdiction Yes/No
 * answer. Selecting >= 2 covered regions auto-suggests "Yes"; the segmented
 * control is an explicit override. Emits resolve {field:'L', value}.
 */
export default class LexproStationLocations extends LightningElement {
    _regions = [];
    _value;
    _manual = false;
    selected = {};
    _selectedRegions = [];
    _seededSel = false;
    otherSelected = false;
    _otherText = '';
    _otherSeeded = false;

    @api
    get regions() {
        return this._regions;
    }
    set regions(val) {
        this._regions = Array.isArray(val) ? val : [];
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
    get selectedRegions() {
        return this._selectedRegions;
    }
    set selectedRegions(val) {
        this._selectedRegions = Array.isArray(val) ? val : [];
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

    // One-time: reflect previously-saved region labels back onto the map.
    trySeed() {
        if (this._seededSel || !this._regions.length || !this._selectedRegions.length) return;
        const byLabel = {};
        this._regions.forEach((r) => {
            byLabel[r.MasterLabel] = r.DeveloperName;
        });
        const sel = {};
        this._selectedRegions.forEach((lbl) => {
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

    selectedLabels() {
        const labels = this._regions
            .filter((r) => this.selected[r.DeveloperName])
            .map((r) => r.MasterLabel);
        if (this.otherSelected) labels.push('Other');
        return labels;
    }

    get mapRegions() {
        return this._regions.map((r) => {
            const isSel = !!this.selected[r.DeveloperName];
            let cls = 'lex-pin';
            if (!r.Covered__c) cls += ' lex-pin_gap';
            if (isSel) cls += ' lex-pin_selected';
            return {
                key: r.DeveloperName,
                label: r.MasterLabel,
                covered: r.Covered__c,
                selected: isSel,
                pressed: isSel ? 'true' : 'false',
                style: `top:${r.Map_Top__c}%; left:${r.Map_Left__c}%;`,
                cls
            };
        });
    }

    get gapNote() {
        const hit = this._regions.find(
            (r) => this.selected[r.DeveloperName] && !r.Covered__c && r.Note__c
        );
        return hit ? hit.Note__c : '';
    }

    get answered() {
        return !!this._value;
    }

    get pickerDisabled() {
        // Once "No" is chosen there is nothing to map — lock the picker.
        return this._value === 'No';
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

    togglePin(event) {
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
        // Selecting a covered region suggests Yes. Never auto-flip to No — the rep
        // chooses No explicitly. Keeps the answer stable while toggling pins.
        const coveredSel = this._regions.filter(
            (r) => this.selected[r.DeveloperName] && r.Covered__c
        ).length;
        if (coveredSel >= 1) this._value = 'Yes';
    }

    pick(event) {
        this._value = event.currentTarget.dataset.val;
        this._manual = true;
        if (this._value === 'No') {
            this.selected = {}; // clear any covered-region picks — answer is No
            this.otherSelected = false;
            this._otherText = '';
        }
        this.emit();
    }

    emit() {
        this.dispatchEvent(
            new CustomEvent('resolve', {
                detail: {
                    field: 'L',
                    value: this._value,
                    regions: this.selectedLabels(),
                    other: this.otherSelected ? this._otherText : ''
                }
            })
        );
    }
}
