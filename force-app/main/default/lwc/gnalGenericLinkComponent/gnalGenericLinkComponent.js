import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import isGuest from '@salesforce/user/isGuest';

export default class GnalGenericLinkComponent extends NavigationMixin(LightningElement) {
  static get ROW_VARIANT_CLASS() {
    return {
      boxed: 'gnal-row--boxed',
      plain: 'gnal-row--plain'
    };
  }

  @api title;
  @api description;
  @api links = [];        // [{ label, url, icon?, rightText?, ariaLabel? }] icon should be a lightning icon name (e.g., utility:info)
  @api learnMoreUrl;      // legacy: optional footer link
  @api footerUrl;         // new: footer link URL
  @api footerLabel = 'Learn More'; // new: footer link label, default like mock
  @api authenticated;     // optional override
  @api variant = 'boxed'; // 'boxed' (default) or 'plain'

  get isAuthenticated() {
    return this.authenticated !== undefined ? this.authenticated : !isGuest;
  }

  get normalizedLinks() {
    const isAuthenticated = this.isAuthenticated;
    const variantClass =
      this.constructor.ROW_VARIANT_CLASS[this.variant] ||
      this.constructor.ROW_VARIANT_CLASS.boxed;
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
      const baseClass = `gnal-row ${variantClass}`;
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
        clickableClass: `${baseClass} gnal-row--link`,
        disabledClass: `${baseClass} gnal-row--disabled`,
        staticClass: baseClass
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
