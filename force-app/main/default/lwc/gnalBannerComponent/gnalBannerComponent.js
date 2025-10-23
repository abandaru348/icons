/**
 * GNALBannerComponent
 * Accessible hero banner with image background and gradient overlay.
 */
import { api, LightningElement } from 'lwc';

export default class GnalBannerComponent extends LightningElement {
  @api backgroundImageUrl;
  @api altText = 'Hero banner';
  @api headline = 'Available Anytime, Anywhere – Always!';
  @api subtitle = '24/7 self-help capabilities, on-demand telehealth registered nurses, and care coordination.';

  get computedBackground(){
    const url = this.backgroundImageUrl || 'https://raw.githubusercontent.com/abandaru348/icons/main/gnalfam.jpg';
    return `background-image:url(${url});`;
  }
}
