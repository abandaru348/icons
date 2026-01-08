import { LightningElement, api } from 'lwc';

export default class GnalCallUsComponent extends LightningElement {
    @api title = 'Call Us';
    @api subtitle = 'Speak directly with a support specialist';
    @api supportLineLabel = 'BH Portal Support Line';
    @api phoneNumberDisplay = '1-800-342-9647';
    @api phoneNumberDial;
    @api availabilityText = 'Available 24 hours a day, 7 days a week';
    @api ctaLabel = 'Call now';

    get telUrl() {
        const dial = (this.phoneNumberDial || this.phoneNumberDisplay || '').trim();
        const normalized = dial.replace(/[^\d+]/g, '');
        return normalized ? `tel:${normalized}` : 'tel:';
    }

    get callAriaLabel() {
        return `Call ${this.phoneNumberDisplay || 'support line'}`;
    }
}
