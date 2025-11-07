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
    const isAuthenticated = this.isAuthenticated;
    return (this.links || []).map((l, i) => {
      const rightText = l.rightText;
      const rightIcon = l.rightIcon;
      const iconBackground = l.iconBackground;
      const iconStyle = iconBackground ? `--gnal-icon-wrapper-bg:${iconBackground}` : undefined;
      const allowGuest = Boolean(l.allowGuest);
      const isDisabled = Boolean(l.disabled) || (!isAuthenticated && !allowGuest);
      const hasUrl = Boolean(l.url);
      const isClickable = hasUrl && !isDisabled;
      const hasRightContent = Boolean(rightText || rightIcon);
      const hasIcon = Boolean(l.icon);
      const ariaLabel = l.ariaLabel || (isClickable ? `Open ${l.label}` : l.label);
      const rowClass = [
        'gnal-row',
        isClickable ? 'gnal-row--clickable' : '',
        isDisabled ? 'gnal-row--disabled' : '',
        !hasIcon ? 'gnal-row--no-icon' : '',
        !hasRightContent ? 'gnal-row--no-meta' : ''
      ]
        .filter(Boolean)
        .join(' ');
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
        hasRightContent,
        rowClass,
        dataClickable: isClickable ? 'true' : 'false',
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
    return this.footerLabel || 'Learn More';
  }

  handleNavigate(event) {
    const { currentTarget } = event;
    if (currentTarget.dataset.clickable !== 'true') {
      return;
    }
    const url = currentTarget.dataset.url;
    if (!url) return;
    this[NavigationMixin.Navigate]({ type: 'standard__webPage', attributes: { url } });
  }

  handleRowKeydown(event) {
    const { key, currentTarget } = event;
    if (key !== 'Enter' && key !== ' ' && key !== 'Spacebar') {
      return;
    }
    if (currentTarget.dataset.clickable !== 'true') {
      return;
    }
    event.preventDefault();
    this.handleNavigate(event);
  }

  handleLearnMore(event) {
    const url = event.currentTarget.dataset.url || this.footerUrlResolved;
    if (!url) return;
    this[NavigationMixin.Navigate]({ type: 'standard__webPage', attributes: { url } });
  }
}
