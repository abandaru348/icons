import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import isGuest from '@salesforce/user/isGuest';

export default class GnalGenericLinkComponent extends NavigationMixin(LightningElement) {
  @api title;
  @api description;
  @api links = [];        // [{ label, url, icon?, rightText?, ariaLabel? }] icon should be a lightning icon name (e.g., utility:info)
  @api learnMoreUrl;      // legacy: optional footer link
  @api footerUrl;         // new: footer link URL
  @api footerLabel = 'Learn More'; // new: footer link label, default like mock
  @api authenticated;     // optional override

  get isAuthenticated() {
    return this.authenticated !== undefined ? this.authenticated : !isGuest;
  }

  get normalizedLinks() {
    return (this.links || []).map((l, i) => {
      const rightText = l.rightText;
      const rightIcon = l.rightIcon;
      const iconBackground = l.iconBackground;
      const iconStyle = iconBackground ? `--gnal-icon-wrapper-bg:${iconBackground}` : undefined;
      return {
        key: l.key || l.label || String(i),
        label: l.label,
        url: l.url,
        icon: l.icon,
        iconStyle,
        subText: l.subText || l.subtitle || l.subLabel,
        ariaLabel: l.ariaLabel || `Open ${l.label}`,
        rightText,
        rightIcon,
        hasRightContent: Boolean(rightText || rightIcon)
      };
    });
  }

  get footerUrlResolved() {
    return this.footerUrl || this.learnMoreUrl;
  }

  get footerLabelResolved() {
    return this.footerLabel || 'Learn More';
  }

  handleNavigate(event) {
    if (!this.isAuthenticated) return;
    const url = event.currentTarget.dataset.url;
    if (!url) return;
    this[NavigationMixin.Navigate]({ type: 'standard__webPage', attributes: { url } });
  }

  handleLearnMore(event) {
    const url = event.currentTarget.dataset.url || this.footerUrlResolved;
    if (!url) return;
    this[NavigationMixin.Navigate]({ type: 'standard__webPage', attributes: { url } });
  }
}
