import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import isGuest from '@salesforce/user/isGuest';

export default class GnalGenericLinkComponent extends NavigationMixin(LightningElement) {
  @api title;
  @api description;
  @api links = [];        // [{ label, url, icon?, rightText?, ariaLabel? }]
  @api learnMoreUrl;      // DEPRECATED: use footerUrl
  @api footerUrl;         // optional footer link
  @api footerLabel = 'Learn More';
  @api authenticated;     // optional override

  get isAuthenticated() {
    return this.authenticated !== undefined ? this.authenticated : !isGuest;
  }

  get normalizedLinks() {
    return (this.links || []).map((l, i) => ({
      key: l.key || l.label || String(i),
      label: l.label,
      url: l.url,
      icon: l.icon,
      rightText: l.rightText,
      ariaLabel: l.ariaLabel || `Open ${l.label}`
    }));
  }

  handleNavigate(event) {
    if (!this.isAuthenticated) return;
    const url = event.currentTarget.dataset.url;
    if (!url) return;
    this[NavigationMixin.Navigate]({ type: 'standard__webPage', attributes: { url } });
  }

  handleLearnMore(event) {
    const url = event.currentTarget.dataset.url || this.footerUrl || this.learnMoreUrl;
    if (!url) return;
    this[NavigationMixin.Navigate]({ type: 'standard__webPage', attributes: { url } });
  }
}
