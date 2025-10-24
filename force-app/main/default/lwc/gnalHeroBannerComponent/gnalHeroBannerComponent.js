import { LightningElement, api, track } from 'lwc';

export default class GnalHeroBannerComponent extends LightningElement {
    @api intervalMs = 6000;
    @api height = '240px';
    @api radius = '10px';

    @api images = [
        { src: '/resource/gnal_fallback_family', alt: 'Family smiling outside' },
        { src: '/resource/gnal_fallback_clinic', alt: 'Clinic building' },
        { src: '/resource/gnal_fallback_care', alt: 'Care coordination' }
    ];

    @track index = 0;
    @track isPaused = false;
    timerId;

    connectedCallback() {
        this.start();
    }

    disconnectedCallback() {
        this.stop();
    }

    start() {
        this.stop();
        this.timerId = window.setInterval(() => {
            if (!this.isPaused) {
                this.index = (this.index + 1) % this.images.length;
            }
        }, this.intervalMs);
    }

    stop() {
        if (this.timerId) {
            window.clearInterval(this.timerId);
            this.timerId = undefined;
        }
    }

    get bannerStyle() {
        const src = (this.images[this.index] && this.images[this.index].src) || '';
        return `height:${this.height};border-radius:${this.radius};background-image:url(${src});`;
    }

    get pauseTitle() {
        return this.isPaused ? 'Play carousel' : 'Pause carousel';
    }

    togglePause() {
        this.isPaused = !this.isPaused;
    }

    handleDot(event) {
        const i = Number(event.currentTarget.dataset.index);
        if (!Number.isNaN(i)) this.index = i;
    }

    get dotClass() {
        return 'dot';
    }
}
