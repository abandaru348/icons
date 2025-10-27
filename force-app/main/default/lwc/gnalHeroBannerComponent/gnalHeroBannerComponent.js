import { LightningElement, api } from 'lwc';
import heroImage from '@salesforce/resourceUrl/gnalfam';

export default class GnalHeroBannerComponent extends LightningElement {
    @api height = '240px';
    @api radius = '10px';
    @api imageSrc = heroImage;

    get bannerStyle() {
        return `height:${this.height};border-radius:${this.radius};background-image:url(${this.imageSrc});`;
    }
}
