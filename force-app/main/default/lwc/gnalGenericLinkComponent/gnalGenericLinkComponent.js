import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import isGuest from '@salesforce/user/isGuest';

const DEFAULT_FOOTER_LABEL = 'Learn More';

export default class GnalGenericLinkComponent extends NavigationMixin(LightningElement) {
  @api title;
  @api description;
  @api links = [];        // [{ label, url, icon?, rightText?, ariaLabel? }], icon should be a lightning icon name (e.g., utility:info)
  @api learnMoreUrl;      // legacy: optional footer link
  @api footerUrl;         // new: footer link URL
  @api footerLabel = DEFAULT_FOOTER_LABEL; // new: footer link label, default like mock
  @api authenticated;     // optional override

  get isAuthenticated() {
    return this.authenticated !== undefined ? this.authenticated : !isGuest;
  }

  get normalizedLinks() {
    return (this.links || []).map((l, i) => {
      const iconClass = l.iconClass;
      const customIcon = this.resolveCustomIcon(l.icon, iconClass);
      return {
        key: l.key || l.label || String(i),
        label: l.label,
        url: l.url,
        icon: l.icon,
        iconClasses: this.computeIconClasses(iconClass),
        iconClassesDisabled: this.computeIconClasses(iconClass, true),
        customIcon,
        subText: l.subText || l.subtitle || l.subLabel,
        rightText: l.rightText,
        ariaLabel: l.ariaLabel || `Open ${l.label}`
      };
    });
  }

  get footerUrlResolved() {
    return this.footerUrl || this.learnMoreUrl;
  }

  get footerLabelResolved() {
    return this.footerLabel || DEFAULT_FOOTER_LABEL;
  }

  handleNavigate(event) {
    if (!this.isAuthenticated) return;
    const url = event.currentTarget.dataset.url;
    this.navigateToUrl(url);
  }

  handleLearnMore(event) {
    const url = event.currentTarget.dataset.url || this.footerUrlResolved;
    this.navigateToUrl(url);
  }

  navigateToUrl(url) {
    if (!url) return;
    this[NavigationMixin.Navigate]({ type: 'standard__webPage', attributes: { url } });
  }

  computeIconClasses(iconClass, disabled = false) {
    const classes = ['gnal-icon'];
    if (iconClass) {
      classes.push(iconClass);
    }
    if (disabled) {
      classes.push('gnal-icon--disabled');
    }
    return classes.join(' ');
  }

  resolveCustomIcon(iconName, iconClass) {
    if (iconName === 'standard:note' && iconClass === 'gnal-icon--appointment') {
      return 'appointment-note';
    }
    return null;
  }
}
