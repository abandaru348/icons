import { LightningElement } from 'lwc';
import DBN_SAMPLE from '@salesforce/resourceUrl/DBN_Sample';

export default class GnalContactUsPage extends LightningElement {
    showDbnInfo = false;
    dbnSampleUrl = DBN_SAMPLE;

    handleToggleDbnInfo() {
        this.showDbnInfo = !this.showDbnInfo;
    }
}

