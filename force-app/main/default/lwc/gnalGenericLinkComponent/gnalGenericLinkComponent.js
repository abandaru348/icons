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

  
}
