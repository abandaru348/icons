import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class GnalTileComponent extends NavigationMixin(LightningElement) {
  static DEFAULT_FOOTER_LABEL = 'Learn More';

  @api title;
  @api description;
  @api links = [];
  @api learnMoreUrl;
  @api footerUrl;
  @api footerLabel;

  get normalizedLinks() {
    return (this.links || []).map((link, index) => {
      const iconName = link.iconName || link.icon;
      const iconClass = ['slds-m-right_small', 'tile-icon'];
      if (link.iconClass) {
        iconClass.push(link.iconClass);
      }

      const styleSegments = [];
      if (link.iconStyle) {
        styleSegments.push(link.iconStyle.trim().replace(/;$/, ''));
      }

      const foreground =
        link.iconForegroundColor || link.iconColor || link.iconColour;
      if (foreground) {
        styleSegments.push(`--slds-c-icon-color-foreground: ${foreground}`);
      }

      const background =
        link.iconBackgroundColor || link.iconBgColor || link.iconBackground;
      if (background) {
        styleSegments.push(`--slds-c-icon-color-background: ${background}`);
      }

      const iconStyle = styleSegments.join('; ');
      const url = link.url?.trim();

      return {
        key: link.key || link.label || `link-${index}`,
        label: link.label,
        url,
        isClickable: Boolean(url),
        iconName,
        iconVariant: link.iconVariant,
        iconSize: link.iconSize || 'small',
        iconClass: iconClass.join(' '),
        iconStyle: iconStyle || undefined,
        alternativeText: link.alternativeText || link.altText || link.label,
        title: link.title || link.label
      };
    });
  }

  get footerUrlResolved() {
    return this.footerUrl || this.learnMoreUrl;
  }

  get footerLabelResolved() {
    return this.footerLabel || this.constructor.DEFAULT_FOOTER_LABEL;
  }

  handleLinkClick(event) {
    event.preventDefault();
    const url = event.currentTarget.dataset.url;
    this.navigateToUrl(url);
  }

  handleLearnMore(event) {
    event.preventDefault();
    const url = event.currentTarget.dataset.url || this.footerUrlResolved;
    this.navigateToUrl(url);
  }

  navigateToUrl(url) {
    if (!url) {
      return;
    }

    this[NavigationMixin.Navigate]({
      type: 'standard__webPage',
      attributes: { url }
    });
  }
}