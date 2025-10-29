import { LightningElement, api } from 'lwc';
import ASSETS from '@salesforce/resourceUrl/GNAL_icons';

export default class GnalHeroBannerComponent extends LightningElement {
    @api height = '260px';
    @api radius = '12px';
    @api imagePath = `${ASSETS}/images/gnalfam.jpg?v=1`;
    @api heroAriaLabel = 'Family smiling outside; My Military Health hero banner';

    get bannerStyle() {
        return `height:${this.height};border-radius:${this.radius};background-image:url(${this.imagePath});`;
    }

    handleImgError(event) {
        const fallback = `${ASSETS}/images/gnalfam.jpg`;
        if (event && event.target) {
            // Prevent infinite loop
            event.target.onerror = null;
            if (event.target.src !== fallback) {
                event.target.src = fallback;
            }
        }
        // Also update background-image style
        this.imagePath = fallback;
    }
}
