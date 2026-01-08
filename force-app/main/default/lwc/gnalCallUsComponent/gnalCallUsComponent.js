/**
 * GNAL Call Us Component
 *
 * Displays a support phone card with a click-to-call CTA, intended for Experience Cloud pages.
 * Phone values are configurable via @api for reuse across brands/environments.
 */

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
        const normalized = this.normalizePhoneForTel(dial);
        return normalized ? `tel:${normalized}` : 'tel:';
    }

    get callAriaLabel() {
        return `Call ${this.phoneNumberDisplay || 'support line'}`;
    }

    /**
     * Normalizes a phone number for tel: links.
     * Keeps digits and an optional leading "+"; removes spaces, hyphens, parentheses, etc.
     */
    normalizePhoneForTel(rawPhone) {
        const input = (rawPhone || '').trim();
        if (!input) {
            return '';
        }

        // Business rule: allow international dialing by preserving "+".
        return input.replace(/[^\d+]/g, '');
    }
}
