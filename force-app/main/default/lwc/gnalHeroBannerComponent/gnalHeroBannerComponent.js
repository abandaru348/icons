import { LightningElement, api } from 'lwc';
import heroImage from '@salesforce/resourceUrl/gnalfam';

export default class GnalHeroBannerComponent extends LightningElement {
    @api height = '260px';
    @api radius = '12px';
    @api imagePath = heroImage;
    @api heroAriaLabel = 'Family smiling outside; My Military Health hero banner';

    get bannerStyle() {
        return `height:${this.height};border-radius:${this.radius};background-image:url(${this.imagePath});`;
    }

    // No runtime handlers needed; image is rendered via CSS background
}
