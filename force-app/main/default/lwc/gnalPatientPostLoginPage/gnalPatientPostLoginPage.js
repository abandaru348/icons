import { LightningElement } from 'lwc';

const DESKTOP_BREAKPOINT = 1024;

export default class GnalPatientPostLoginPage extends LightningElement {
    resizeHandler;

    connectedCallback() {
        if (typeof window === 'undefined') {
            return;
        }

        this.resizeHandler = () => {
            window.requestAnimationFrame(() => this.equalizeTiles());
        };
        window.addEventListener('resize', this.resizeHandler);
    }

    renderedCallback() {
        if (typeof window !== 'undefined') {
            window.requestAnimationFrame(() => this.equalizeTiles());
        } else {
            this.equalizeTiles();
        }
    }

    disconnectedCallback() {
        if (this.resizeHandler && typeof window !== 'undefined') {
            window.removeEventListener('resize', this.resizeHandler);
            this.resizeHandler = undefined;
        }
    }

    equalizeTiles() {
        const tiles = Array.from(this.template.querySelectorAll('[data-tile]'));

        if (!tiles.length) {
            return;
        }

        tiles.forEach((tile) => {
            tile.style.minHeight = '';
        });

        if (typeof window === 'undefined' || window.innerWidth < DESKTOP_BREAKPOINT) {
            return;
        }

        const maxHeight = tiles.reduce((max, tile) => Math.max(max, tile.offsetHeight), 0);

        if (maxHeight > 0) {
            tiles.forEach((tile) => {
                tile.style.minHeight = `${maxHeight}px`;
            });
        }
    }
}
