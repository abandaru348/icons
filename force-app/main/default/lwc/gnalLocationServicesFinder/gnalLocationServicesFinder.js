import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { decodeDefaultFieldValues } from 'lightning/pageReferenceUtils';
import getDefaultCurrentLocationForCase from '@salesforce/apex/GnalLocationServicesController.getDefaultCurrentLocationForCase';
import createOrIncrementLocationService from '@salesforce/apex/GnalLocationServicesController.createOrIncrementLocationService';
import findNearestFacilitiesWithRadius from '@salesforce/apex/GnalFacilitySearchController.findNearestFacilitiesWithRadius';

export default class GnalLocationServicesFinder extends LightningElement {
    static WARM_CACHE_RADIUS_MILES = 100;

    @api recordId; // Case Id when placed on Case page as an action
    caseId;

    currentLocation = '';
    isLoading = false;
    noticeMessage = '';
    results = [];

    get hasResults() {
        return this.results && this.results.length > 0;
    }

    @wire(CurrentPageReference)
    setPageRef(pr) {
        // When used as a New override from the Case related list, Case__c may come through defaultFieldValues.
        try {
            const defaults = pr?.state?.defaultFieldValues;
            if (defaults && !this.caseId && !this.recordId) {
                const decoded = decodeDefaultFieldValues(defaults);
                if (decoded?.Case__c) this.caseId = decoded.Case__c;
            }
        } catch (e) {
            // ignore
        }
    }

    connectedCallback() {
        // Prefer explicit recordId (Case quick action), else fall back to Case__c from defaultFieldValues.
        this.caseId = this.recordId || this.caseId;
        if (!this.caseId) return;
        getDefaultCurrentLocationForCase({ caseId: this.caseId })
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
        const effectiveCaseId = this.recordId || this.caseId;

        if (!effectiveCaseId) {
            this.noticeMessage = 'This action must be run from a Case.';
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
                caseId: effectiveCaseId,
                currentLocation: normalized
            });
            const count = upsert?.searchCount;
            this.noticeMessage = count ? `Search count: ${count}` : 'Search recorded.';

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

