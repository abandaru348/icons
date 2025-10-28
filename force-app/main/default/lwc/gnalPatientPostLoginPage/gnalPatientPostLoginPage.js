import { LightningElement } from 'lwc';
import { loadStyle } from 'lightning/platformResourceLoader';
import ASSETS from '@salesforce/resourceUrl/mymh_assets';
export default class GnalPatientPostLoginPage extends LightningElement {
    connectedCallback() {
        loadStyle(this, `${ASSETS}/css/mymh_global.css`);
    }
}
