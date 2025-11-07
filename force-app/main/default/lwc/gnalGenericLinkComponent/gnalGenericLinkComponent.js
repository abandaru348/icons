import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import isGuest from '@salesforce/user/isGuest';

export default class GnalGenericLinkComponent extends NavigationMixin(LightningElement) {
  static DEFAULT_FOOTER_LABEL = 'Learn More';

  @api title;
  @api description;
  @api links = [];        // [{ label, url, icon?, rightText?, ariaLabel? }] icon should be a lightning icon name (e.g., utility:info)
  @api learnMoreUrl;      // legacy: optional footer link
  @api footerUrl;         // new: footer link URL
  @api footerLabel;       // new: footer link label, default like mock
  @api authenticated;     // optional override
  @api variant = 'boxed'; // 'boxed' (default) or 'plain'

  get isAuthenticated() {
    return this.authenticated !== undefined ? this.authenticated : !isGuest;
  }

  get normalizedLinks() {
    const isAuthenticated = this.isAuthenticated;
    const isPlain = this.variant === 'plain';
    const variantClass = isPlain ? 'row--plain' : 'row--boxed';
    return (this.links || []).map((l, i) => {
      const rightText = l.rightText;
      const rightIcon = l.rightIcon;
      const iconBackground = l.iconBackground;
      const iconStyle = iconBackground ? `--gnal-icon-wrapper-bg:${iconBackground}` : undefined;
      const allowGuest = Boolean(l.allowGuest);
      const isDisabled = Boolean(l.disabled) || (!isAuthenticated && !allowGuest);
      const hasUrl = Boolean(l.url);
      const isClickable = !isDisabled && hasUrl;
      const ariaLabel = l.ariaLabel || (isClickable ? `Open ${l.label}` : l.label);
      const rowClassList = [
        'row',
        'slds-grid',
        'slds-grid_vertical-align-center',
        'slds-grid_align-spread',
        'slds-gutters_small',
        isPlain ? 'slds-p-vertical_small' : 'slds-p-around_small',
        isPlain ? 'slds-p-horizontal_none' : undefined,
        variantClass
      ].filter(Boolean);
      if (isClickable) {
        rowClassList.push('row--link');
      }
      if (isDisabled) {
        rowClassList.push('row--disabled');
      }
      return {
        key: l.key || l.label || String(i),
        label: l.label,
        url: l.url,
        icon: l.icon,
        iconStyle,
        subText: l.subText || l.subtitle || l.subLabel,
        ariaLabel,
        rightText,
        rightIcon,
        hasRightContent: Boolean(rightText || rightIcon),
        isClickable,
        isDisabled,
        rowClass: rowClassList.join(' '),
        role: isClickable ? 'link' : undefined,
        tabIndex: isClickable ? '0' : undefined,
        ariaDisabled: isDisabled ? 'true' : undefined
      };
    });
  }

  get footerUrlResolved() {
    return this.footerUrl || this.learnMoreUrl;
  }

  get footerLabelResolved() {
    return this.footerLabel || this.constructor.DEFAULT_FOOTER_LABEL;
  }

  handleNavigate(event) {
    if (!this.isAuthenticated) return;
    const isClickable = event.currentTarget.dataset.clickable === 'true';
    if (!isClickable) return;
    const url = event.currentTarget.dataset.url;
    if (!url) return;
    this[NavigationMixin.Navigate]({ type: 'standard__webPage', attributes: { url } });
  }

  handleLearnMore(event) {
    const url = event.currentTarget.dataset.url || this.footerUrlResolved;
    if (!url) return;
    this[NavigationMixin.Navigate]({ type: 'standard__webPage', attributes: { url } });
  }

  handleKeydown(event) {
    if (event.key !== 'Enter' && event.key !== ' ') {
      return;
    }
    const isClickable = event.currentTarget.dataset.clickable === 'true';
    if (!isClickable) {
      return;
    }
    event.preventDefault();
    this.handleNavigate(event);
  }
}
