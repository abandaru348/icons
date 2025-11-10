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

  get footerUrlResolved() {
    return this.footerUrl || this.learnMoreUrl;
  }

  get footerLabelResolved() {
    return this.footerLabel || this.constructor.DEFAULT_FOOTER_LABEL;
  }

  handleLearnMore(event) {
    const url = event.currentTarget.dataset.url || this.footerUrlResolved;
    this.navigateToUrl(url);
  }

  navigateToUrl(url) {
    if (!url) {
      return;
    }

    this[NavigationMixin.Navigate]({
      type: 'standard__webPage',
      attributes: {
        url,
      },
    });
  }
}
