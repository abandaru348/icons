import { LightningElement } from 'lwc';
import GNAL_LOGO from '@salesforce/resourceUrl/GNALLogo';

export default class GnalAccountCreationPage extends LightningElement {
    logo = GNAL_LOGO;

    handleSubmit(event) {
        event.preventDefault();
    }
}
