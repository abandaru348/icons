import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class GnalTileComponent extends NavigationMixin(LightningElement) {
    static DEFAULT_FOOTER_LABEL = 'Learn More';

    @api title;
    @api description;
    @api links = [];
    @api learnMoreUrl;
    @api footerUrl;
    @api footerLabel;
    @api variant = 'default';

    get footerUrlResolved() {
        return this.footerUrl || this.learnMoreUrl;
    }

    get footerLabelResolved() {
        return this.footerLabel || this.constructor.DEFAULT_FOOTER_LABEL;
    }

    get linkClass() {
        const classes = ['tile-link', 'slds-grid', 'slds-grid_vertical-align-center'];
        if (this.variant === 'prelogin') {
            classes.push('tile-link--neutral');
        }
        return classes.join(' ');
    }

    handleLearnMore(event) {
        event.preventDefault();
    }

    handleLinkClick(event) {
        event.preventDefault();
        const url = event.currentTarget.dataset.url;
        this.openInNewTab(url);
    }

    openInNewTab(url) {
        if (!url) {
            return;
        }

        window.open(url, '_blank', 'noopener,noreferrer');
    }
}
