import { LightningElement, api } from 'lwc';
import getDefaultCurrentLocationForCase from '@salesforce/apex/GnalLocationServicesController.getDefaultCurrentLocationForCase';
import createOrIncrementLocationService from '@salesforce/apex/GnalLocationServicesController.createOrIncrementLocationService';
import findNearestFacilitiesWithRadius from '@salesforce/apex/GnalFacilitySearchController.findNearestFacilitiesWithRadius';

export default class GnalLocationServicesFinder extends LightningElement {
    static WARM_CACHE_RADIUS_MILES = 100;

    @api recordId; // Case Id when placed on Case page/quick action
    currentLocation = '';
    isLoading = false;
    noticeMessage = '';
    results = [];

    get hasResults() {
        return this.results && this.results.length > 0;
    }

    connectedCallback() {
        if (!this.recordId) return;
        getDefaultCurrentLocationForCase({ caseId: this.recordId })
            .then((addr) => {
                if (addr) this.currentLocation = addr;
            })
            .catch(() => {
                // non-blocking
            });
    }

    handleLocationChange(event) {
        this.currentLocation = (event.target.value || '').trim();
    }

    normalizeResults(data = []) {
        return (data || []).map((r) => {
            const minutesNum = Number(r?.minutes ?? 0);
            const milesNum = Number(r?.distanceMiles ?? 0);
            const safeMinutes = Number.isFinite(minutesNum) ? minutesNum : 0;
            const safeMiles = Number.isFinite(milesNum) ? milesNum : 0;
            return {
                ...r,
                minutes: safeMinutes,
                distanceMiles: safeMiles,
                info: `${Math.round(safeMinutes)} mins (${safeMiles.toFixed(1)} mi)`
            };
        });
    }

    async handleFind() {
        const normalized = (this.currentLocation || '').trim();
        this.currentLocation = normalized;
        if (!this.recordId) {
            this.noticeMessage = 'This action must be run from a Case record.';
            return;
        }
        if (!normalized) {
            this.noticeMessage = 'Current Location is required.';
            return;
        }

        this.isLoading = true;
        this.noticeMessage = '';
        this.results = [];
        try {
            const upsert = await createOrIncrementLocationService({
                caseId: this.recordId,
                currentLocation: normalized
            });
            const count = upsert?.searchCount;
            this.noticeMessage =
                count ? `Search count for this location: ${count}` : 'Search recorded.';

            const data = await findNearestFacilitiesWithRadius({
                accountId: null,
                originAddress: normalized,
                radiusMiles: GnalLocationServicesFinder.WARM_CACHE_RADIUS_MILES
            });
            this.results = this.normalizeResults(data);
        } catch (e) {
            this.noticeMessage = e?.body?.message || e?.message || 'Error running search.';
        } finally {
            this.isLoading = false;
        }
    }
}

