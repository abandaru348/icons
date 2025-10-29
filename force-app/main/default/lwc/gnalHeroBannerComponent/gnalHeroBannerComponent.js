import { LightningElement, api } from 'lwc';
import ASSETS from '@salesforce/resourceUrl/GNAL_icons';

export default class GnalHeroBannerComponent extends LightningElement {
    @api height = '260px';
    @api radius = '12px';
    @api imagePath = `${ASSETS}/images/hero-banner.jpg`;
    @api heroAriaLabel = 'Family smiling outside; My Military Health hero banner';

    get bannerStyle() {
        return `height:${this.height};border-radius:${this.radius};background-image:url(${this.imagePath});`;
    }

    connectedCallback() {
        // Preload hero image with fallback to legacy gnalfam.jpg if not present in the org
        const candidates = [
            `${ASSETS}/images/hero-banner.jpg`,
            `${ASSETS}/images/gnalfam.jpg`
        ];
        this.preloadSequentially(candidates, 0);
    }

    preloadSequentially(paths, index) {
        if (!Array.isArray(paths) || index >= paths.length) return;
        const testImg = new Image();
        testImg.onload = () => {
            this.imagePath = paths[index];
        };
        testImg.onerror = () => this.preloadSequentially(paths, index + 1);
        testImg.src = paths[index];
    }
}
