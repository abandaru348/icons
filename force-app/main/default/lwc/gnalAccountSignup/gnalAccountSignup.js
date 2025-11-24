import { LightningElement } from 'lwc';

export default class GnalAccountSignup extends LightningElement {
    isTermsChecked = false;

    handleTermsChange(event) {
        this.isTermsChecked = event.target.checked;
    }

    handleSubmit(event) {
        event.preventDefault();
        const createEvent = new CustomEvent('createaccount', {
            detail: { termsAccepted: this.isTermsChecked }
        });
        this.dispatchEvent(createEvent);
    }

    get isCreateDisabled() {
        return !this.isTermsChecked;
    }
}
