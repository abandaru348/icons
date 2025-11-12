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
      const iconClass = ['slds-m-right_small'];
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

      return {
        key: link.key || link.label || `link-${index}`,
        label: link.label,
        url: link.url,
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

  handleLearnMore(event) {
    const url = event.currentTarget.dataset.url || this.footerUrlResolved;
    this.navigateToUrl(url);
  }
}