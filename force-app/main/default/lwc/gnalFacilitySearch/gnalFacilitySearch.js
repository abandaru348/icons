import { LightningElement, api, track } from 'lwc';
import getAccountBillingAddress from '@salesforce/apex/GnalFacilitySearchController.getAccountBillingAddress';
import getLatestCaseOriginAddress from '@salesforce/apex/GnalFacilitySearchController.getLatestCaseOriginAddress';
import findNearestFacilitiesWithRadius from '@salesforce/apex/GnalFacilitySearchController.findNearestFacilitiesWithRadius';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class FindNearestFacilities extends LightningElement {
    static LIST_RESULT_LIMIT = 8;
    static MAP_MARKER_LIMIT = 5;

    @api recordId;
    @track originAddress = '';
    @track results = [];
    @track isLoading = false;
    @track showFinder = false;
    @track mapMarkers = [];
    @track mapCenter;
    @track selectedDistance = '15';
    searchHasRun = false;

    get hasResults() {
        return this.results && this.results.length > 0;
    }

    get distanceOptions() {
        return [
            { label: '5 miles', value: '5' },
            { label: '15 miles', value: '15' },
            { label: '25 miles', value: '25' },
            { label: '100 miles', value: '100' }
        ];
    }

    connectedCallback() {
        this.initializeOriginAddress();
    }

    initializeOriginAddress() {
        // Requirement: origin should be prepopulated from latest matching Case for logged-in user,
        // fallback to Account billing address.
        getLatestCaseOriginAddress()
            .then((caseOrigin) => {
                if (caseOrigin) {
                    this.originAddress = caseOrigin;
                    return null;
                }
                return getAccountBillingAddress({ accountId: this.recordId });
            })
            .then((billingAddress) => {
                if (billingAddress && !this.originAddress) {
                    this.originAddress = billingAddress;
                }
            })
            .catch((error) => {
                // eslint-disable-next-line no-console
                console.error('Error initializing origin address', error);
            });
    }

    handleShowFinder() {
        this.showFinder = true;
    }

    handleCancel() {
        this.showFinder = false;
        this.results = [];
        this.mapMarkers = [];
        this.mapCenter = undefined;
        this.searchHasRun = false;
        this.selectedDistance = '15';
    }

    handleAddressChange(event) {
        this.originAddress = event.target.value;
    }

    handleDistanceChange(event) {
        this.selectedDistance = event.detail.value;
        if (!this.searchHasRun || this.isLoading) {
            return;
        }
        // Radius change triggers a lightweight SOQL distance filter; no Google calls when cache is warm.
        this.executeSearch({ showToastOnSuccess: false });
    }

    handleFind() {
        this.executeSearch({ showToastOnSuccess: true });
    }

    getErrorMessage(error) {
        // Handles common Salesforce error shapes (Apex, LDS, network)
        if (!error) return 'Unknown error';
        if (typeof error === 'string') return error;
        if (error?.body) {
            if (typeof error.body === 'string') return error.body;
            if (Array.isArray(error.body)) {
                const msgs = error.body.map((e) => e?.message).filter(Boolean);
                if (msgs.length) return msgs.join(', ');
            }
            if (error.body?.message) return error.body.message;
            if (error.body?.pageErrors?.length) return error.body.pageErrors.map((e) => e?.message).filter(Boolean).join(', ');
            if (error.body?.fieldErrors) {
                const fieldMsgs = Object.values(error.body.fieldErrors)
                    .flat()
                    .map((e) => e?.message)
                    .filter(Boolean);
                if (fieldMsgs.length) return fieldMsgs.join(', ');
            }
        }
        if (error?.message) return error.message;
        try {
            return JSON.stringify(error);
        } catch (e) {
            return 'Unknown error';
        }
    }

    executeSearch({ showToastOnSuccess }) {
        if (!this.originAddress) {
            this.showToast('Error', 'Please provide an origin address.', 'error');
            return;
        }

        this.isLoading = true;
        const radius = Number(this.selectedDistance);
        const payload = {
            accountId: this.recordId,
            originAddress: this.originAddress,
            radiusMiles: isNaN(radius) ? null : radius
        };

        findNearestFacilitiesWithRadius(payload)
            .then((data = []) => {
                const normalized = data.map((r) => ({
                    ...r,
                    info: `${Math.round(r.minutes ?? 0)} mins (${(r.distanceMiles ?? 0).toFixed(1)} mi)`
                }));

                const listResults = normalized.slice(0, FindNearestFacilities.LIST_RESULT_LIMIT);
                const markerResults = normalized.slice(0, FindNearestFacilities.MAP_MARKER_LIMIT);

                this.results = listResults;
                this.updateMap(markerResults);
                this.searchHasRun = true;

                if (showToastOnSuccess) {
                    this.showToast('Success', 'Nearest facilities found successfully.', 'success');
                }
            })
            .catch((error) => {
                // eslint-disable-next-line no-console
                console.error('Error finding facilities:', error);
                this.showToast('Error', this.getErrorMessage(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    updateMap(resultsForMap) {
        if (!resultsForMap || !resultsForMap.length) {
            this.mapMarkers = [];
            this.mapCenter = undefined;
            return;
        }

        const markers = resultsForMap.map((result, index) => {
            const hasLatLng =
                result.latitude !== null &&
                result.latitude !== undefined &&
                result.longitude !== null &&
                result.longitude !== undefined;

            return {
                location: hasLatLng
                    ? { Latitude: result.latitude, Longitude: result.longitude }
                    : { Street: result.address },
                value: `${result.address}-${index}`,
                title: `Facility ${index + 1}`,
                description: result.info
            };
        });

        this.mapMarkers = markers;

        const firstWithCoords = markers.find(
            (marker) => marker.location.Latitude !== undefined && marker.location.Longitude !== undefined
        );

        this.mapCenter = firstWithCoords
            ? {
                  location: {
                      Latitude: firstWithCoords.location.Latitude,
                      Longitude: firstWithCoords.location.Longitude
                  }
              }
            : undefined;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    get googleMapSearchUrl() {
        if (!this.hasResults) return null;
        const address = this.results[0].address;
        return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(address)}`;
    }

    handleOpenInMaps() {
        const url = this.googleMapSearchUrl;
        if (url) {
            window.open(url, '_blank');
        }
    }
}
