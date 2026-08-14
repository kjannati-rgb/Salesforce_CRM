import { LightningElement, api } from 'lwc';

/**
 * Thin wrapper so Smart Convert can be launched as a Lead quick-action (screen action).
 * It just hosts the smartConvert component and hands it the record id.
 */
export default class SmartConvertAction extends LightningElement {
    @api recordId;
}
