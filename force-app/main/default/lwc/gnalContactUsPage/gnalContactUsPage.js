import { LightningElement } from 'lwc';
import DBN_SAMPLE from '@salesforce/resourceUrl/DBN_Sample';
import SUPPORT_PHONE from '@salesforce/label/c.GNAL_Portal_Support_Phone';
import SUPPORT_EMAIL from '@salesforce/label/c.GNAL_Portal_Support_Email';

export default class GnalContactUsPage extends LightningElement {
    showDbnInfo = false;
    dbnSampleUrl = DBN_SAMPLE;
    supportPhone = SUPPORT_PHONE;
    supportEmail = SUPPORT_EMAIL;

    handleToggleDbnInfo() {
        this.showDbnInfo = !this.showDbnInfo;
    }

    handleEmailClick() {
        window.location.href = `mailto:${this.supportEmail}`;
    }

    handleChatClick() {
        // Chat implementation depends on the Experience Cloud site's chat provider.
        // Keeping this handler in place so the UI is wired correctly.
    }
}

