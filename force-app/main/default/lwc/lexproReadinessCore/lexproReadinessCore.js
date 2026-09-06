import { LightningElement, api } from 'lwc';

const R = 52;
const CIRC = 2 * Math.PI * R; // ~326.73

/**
 * REV-69 — readiness core. Presentational.
 * Renders the progress ring (fills in Lexology blue), the fit pill, and the
 * locked "Advance to Qualify" button. Emits advance when clicked.
 */
export default class LexproReadinessCore extends LightningElement {
    @api count = 0;
    @api complete = false;
    @api fit = 'Pending';
    @api submitted = false;

    get ringStyle() {
        const fraction = Math.max(0, Math.min(3, this.count)) / 3;
        const fill = (fraction * CIRC).toFixed(1);
        return `stroke-dasharray:${fill} ${CIRC.toFixed(1)};`;
    }

    get progressLabel() {
        return `${this.count} of 3 resolved`;
    }

    get fitLabel() {
        return `Fit: ${this.fit}`;
    }

    get fitClass() {
        const map = {
            Strong: 'lex-fit lex-fit_strong',
            Moderate: 'lex-fit lex-fit_moderate',
            Caution: 'lex-fit lex-fit_caution'
        };
        return map[this.fit] || 'lex-fit lex-fit_pending';
    }

    get buttonDisabled() {
        return !this.complete || this.submitted;
    }

    get buttonLabel() {
        if (this.submitted) return 'Advanced to Qualify';
        return this.complete ? 'Advance to Qualify' : this.progressLabel;
    }

    handleAdvance() {
        this.dispatchEvent(new CustomEvent('advance'));
    }
}
