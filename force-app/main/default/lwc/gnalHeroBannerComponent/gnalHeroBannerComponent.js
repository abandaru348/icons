import { LightningElement, api } from 'lwc';

export default class GnalHeroBannerComponent extends LightningElement {
    @api height = '240px';
    @api radius = '10px';
    @api imageSrc = '/resource/gnal_fallback_family';

    get bannerStyle() {
        return `height:${this.height};border-radius:${this.radius};background-image:url(${this.imageSrc});`;
    }
}
