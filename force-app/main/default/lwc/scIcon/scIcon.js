import { LightningElement, api } from 'lwc';

// Line-icon set (stroke, inherits currentColor) — replaces emoji across Smart Convert.
const ICONS = {
    company: ['M3 21h18', 'M6 21V4h9v17', 'M15 21V9h4v12', 'M9 8h3M9 12h3M9 16h3'],
    link: ['M9.5 14.5l5-5', 'M10 7l1-1a3.5 3.5 0 015 5l-1 1', 'M14 17l-1 1a3.5 3.5 0 01-5-5l1-1'],
    refresh: ['M20 11a8 8 0 10-2.3 5.6', 'M20 5v6h-6'],
    trending: ['M3 17l6-6 4 4 8-8', 'M21 7v6h-6'],
    wand: ['M5 21L16 10', 'M14 4l1 2 2 1-2 1-1 2-1-2-2-1 2-1 1-2z', 'M19 11l.6 1.4L21 13l-1.4.6L19 15l-.6-1.4L17 13l1.4-.6z'],
    location: ['M12 21s6.5-6 6.5-10.5a6.5 6.5 0 10-13 0C5.5 15 12 21 12 21z', 'M12 12.5a2.2 2.2 0 100-4.5 2.2 2.2 0 000 4.5z'],
    opportunity: ['M4 8h16v10a1 1 0 01-1 1H5a1 1 0 01-1-1V8z', 'M9 8V6a2 2 0 012-2h2a2 2 0 012 2v2'],
    warning: ['M12 4l8.5 15H3.5L12 4z', 'M12 10v4', 'M12 17h.01'],
    add: ['M12 6v12', 'M6 12h12'],
    user: ['M12 12a3.5 3.5 0 100-7 3.5 3.5 0 000 7z', 'M5 20c0-3 3.1-5.5 7-5.5s7 2.5 7 5.5'],
    check: ['M5 12l4.5 4.5L19 6.5'],
    bolt: ['M13 3L5 13h6l-2 8 9-11h-6l1-7z'],
    ban: ['M12 21a9 9 0 100-18 9 9 0 000 18z', 'M6 6l12 12'],
    mail: ['M4 6h16v12H4z', 'M4 7l8 6 8-6'],
    shield: ['M12 3l7.5 2.8v5.5c0 4.3-3 7.4-7.5 8.7-4.5-1.3-7.5-4.4-7.5-8.7V5.8L12 3z', 'M9 12l2 2 4-4'],
    scale: ['M12 4v16', 'M7 20h10', 'M12 6l-5 4h10l-5-4z'],
    search: ['M11 18a7 7 0 100-14 7 7 0 000 14z', 'M20 20l-3.5-3.5'],
    target: ['M12 21a9 9 0 100-18 9 9 0 000 18z', 'M12 16a4 4 0 100-8 4 4 0 000 8z', 'M12 13a1 1 0 100-2 1 1 0 000 2z'],
    layout: ['M4 5h16v14H4z', 'M4 10h16', 'M10 10v9'],
    chevron: ['M6 9l6 6 6-6']
};

export default class ScIcon extends LightningElement {
    @api name;
    @api size = 20;
    get paths() {
        return ICONS[this.name] || [];
    }
    get svgStyle() {
        return `width:${this.size}px;height:${this.size}px;display:inline-block;vertical-align:middle`;
    }
}
