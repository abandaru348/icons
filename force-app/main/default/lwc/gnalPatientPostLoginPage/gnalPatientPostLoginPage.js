import { LightningElement } from 'lwc';
import { loadStyle } from 'lightning/platformResourceLoader';
import ASSETS from '@salesforce/resourceUrl/GNAL_Icons';
export default class GnalPatientPostLoginPage extends LightningElement {
    connectedCallback() {
        // Load shared global css; fail gracefully if not available
        loadStyle(this, `${ASSETS}/css/mymh_global.css`).catch(() => {
            // eslint-disable-next-line no-console
            console.warn('GNAL_icons: failed to load global CSS');
        });
    }
}
