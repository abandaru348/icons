import { LightningElement } from 'lwc';
import { loadStyle } from 'lightning/platformResourceLoader';
import ASSETS from '@salesforce/resourceUrl/GNAL_icons';
export default class GnalPatientPostLoginPage extends LightningElement {
    connectedCallback() {
        loadStyle(this, `${ASSETS}/css/mymh_global.css`);
    }
}
