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
    return (this.links || []).map((l, i) => ({
      key: l.key || l.label || String(i),
      label: l.label,
      url: l.url,
      icon: l.icon,
      subText: l.subText || l.subtitle || l.subLabel,
      rightText: l.rightText,
      ariaLabel: l.ariaLabel || `Open ${l.label}`
    }));
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
