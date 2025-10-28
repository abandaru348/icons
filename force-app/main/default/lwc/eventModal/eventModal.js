import { LightningElement, api } from 'lwc';

export default class EventModal extends LightningElement {
    @api open = false;
    @api title = '';
    @api when = '';
    @api imageUrl = '';
    @api description1 = '';
    @api description2 = '';
    @api featuredLabel = 'Featured';
    @api categoryLabel = 'Mental Well-Being';

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleBackdropClick() {
        this.handleClose();
    }

    handleEnroll() {
        this.dispatchEvent(new CustomEvent('enroll'));
    }
}

