import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

const DEFAULT_ICON_FOREGROUND = '#ffffff';

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
      (iconBackground ? DEFAULT_ICON_FOREGROUND : undefined);

    const iconClassList = ['tile-icon'];

    if (link.iconClass) {
      iconClassList.push(link.iconClass);
    }

    return {
      key: link.key || link.label || String(index),
      label: link.label,
      url: link.url,
      iconName: link.iconName || link.icon,
      iconClass: iconClassList.join(' '),
      iconStyle: this.buildIconStyle(iconBackground, iconForeground),
      ariaLabel: link.ariaLabel || `Open ${link.label}`,
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

  handleLearnMore(event) {
    const url = event.currentTarget.dataset.url || this.footerUrlResolved;
    this.navigateToUrl(url);
  }

  handleLinkClick(event) {
    const url = event.currentTarget.dataset.url;
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
