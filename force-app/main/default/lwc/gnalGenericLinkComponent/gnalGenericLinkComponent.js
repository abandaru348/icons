import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import isGuest from '@salesforce/user/isGuest';


export default class GnalGenericLinkComponent extends NavigationMixin(LightningElement) {
  
  static DEFAULT_FOOTER_LABEL = 'Learn More';

  @api title;
  @api description;
  @api links = [];        
  @api learnMoreUrl;      
  @api footerUrl;         
  @api footerLabel; 
  @api authenticated;     

  get isAuthenticated() {
    return this.authenticated !== undefined ? this.authenticated : !isGuest;
  }

  get normalizedLinks() {
    return (this.links || []).map((link, index) => this.normalizeLink(link, index));
  }

  normalizeLink(link, index) {
    const iconBackground =
      link.iconBackground ??
      link.iconBackgroundColor ??
      link.iconBgColor ??
      link.iconColorBackground ??
      link.iconColor;

    const iconForeground =
      link.iconForeground ??
      link.iconForegroundColor ??
      link.iconFgColor ??
      link.iconColorForeground ??
      (iconBackground ? '#ffffff' : undefined);

    const iconClassList = ['gnal-icon', 'icon--appointment'];

    if (link.iconClass) {
      iconClassList.push(link.iconClass);
    }

    return {
      key: link.key || link.label || String(index),
      label: link.label,
      url: link.url,
      icon: link.icon,
      iconVariant: link.iconVariant,
      iconClass: iconClassList.join(' '),
      iconStyle: this.buildIconStyle(iconBackground, iconForeground),
      subText: link.subText || link.subtitle || link.subLabel,
      rightText: link.rightText,
      ariaLabel: link.ariaLabel || `Open ${link.label}`
    };
  }

  buildIconStyle(iconBackground, iconForeground) {
    const styleParts = [];

    if (iconBackground) {
      styleParts.push(`--slds-c-icon-color-background: ${iconBackground}`);
    }

    if (iconForeground) {
      styleParts.push(`--slds-c-icon-color-foreground: ${iconForeground}`);
    }

    return styleParts.length ? styleParts.join('; ') : undefined;
  }

  get footerUrlResolved() {
    return this.footerUrl || this.learnMoreUrl;
  }

  get footerLabelResolved() {

    return this.footerLabel || this.constructor.DEFAULT_FOOTER_LABEL;
  }

  get rowClass() {
    const baseClass = 'slds-grid slds-grid_vertical-align-center slds-grid_align-spread gnal-row';
    return this.isAuthenticated ? `${baseClass} slds-text-link_reset gnal-link` : `${baseClass} gnal-item-disabled`;
  }

  get disabledState() {
    return this.isAuthenticated ? 'false' : 'true';
  }

  get rowTabIndex() {
    return this.isAuthenticated ? '0' : '-1';
  }
   

  handleNavigate(event) {
    if (!this.isAuthenticated) return;
    const url = event.currentTarget.dataset.url;
    this.navigateToUrl(url);
  }

  handleRowKeydown(event) {
    if (!this.isAuthenticated) return;
    const { key } = event;
    if (key === 'Enter' || key === ' ' || key === 'Spacebar') {
      event.preventDefault();
      this.handleNavigate(event);
    }
  }

  handleLearnMore(event) {
    const url = event.currentTarget.dataset.url || this.footerUrlResolved;
    this.navigateToUrl(url);
  }

  navigateToUrl(url) {
    if (!url) return;
    this[NavigationMixin.Navigate]({ type: 'standard__webPage', attributes: { url } }); 
  }

  
}
