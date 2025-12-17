import { LightningElement, api, track } from 'lwc';
import getAccountBillingAddress from '@salesforce/apex/GnalFacilitySearchController.getAccountBillingAddress';
import getLatestCaseOriginAddressForAccount from '@salesforce/apex/GnalFacilitySearchController.getLatestCaseOriginAddressForAccount';
import findNearestFacilitiesWithRadius from '@salesforce/apex/GnalFacilitySearchController.findNearestFacilitiesWithRadius';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class FindNearestFacilities extends LightningElement {
    static LIST_RESULT_LIMIT = 8;
    static MAP_MARKER_LIMIT = 5;

    _recordId;
    _didInitOrigin = false;
    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        // On record pages, recordId may be undefined during connectedCallback.
        // Initialize only once we actually have an Account Id.
        if (this._recordId && !this._didInitOrigin) {
            this._didInitOrigin = true;
            this.initializeOriginAddress();
        }
    }
    @track originAddress = '';
    @track allResults = [];
    @track results = [];
    @track isLoading = false;
    @track showFinder = false;
    @track mapMarkers = [];
    @track mapCenter;
    @track selectedDistance = '15';
    @track lastErrorMessage = '';
    @track lastErrorDetails = '';
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

    connectedCallback() {}

    initializeOriginAddress() {
        // Requirement: origin should be prepopulated from latest matching Case for logged-in user,
        // fallback to Account billing address.
        if (!this.recordId) {
            return;
        }
        getLatestCaseOriginAddressForAccount({ accountId: this.recordId })
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
                const msg = this.getErrorMessage(error);
                this.lastErrorMessage = msg;
                this.lastErrorDetails = this.getErrorDetails(error);
            });
    }

    handleShowFinder() {
        this.showFinder = true;
    }

    handleCancel() {
        this.showFinder = false;
        this.allResults = [];
        this.results = [];
        this.mapMarkers = [];
        this.mapCenter = undefined;
        this.searchHasRun = false;
        this.selectedDistance = '15';
        this.lastErrorMessage = '';
        this.lastErrorDetails = '';
    }

    handleAddressChange(event) {
        this.originAddress = event.target.value;
    }

    handleDistanceChange(event) {
        this.selectedDistance = event.detail.value;
        if (!this.searchHasRun || this.isLoading) {
            return;
        }
        const radius = Number(this.selectedDistance);
        this.applyRadiusFilter(isNaN(radius) ? null : radius);
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

    applyRadiusFilter(radiusMiles) {
        const effectiveRadius = radiusMiles && radiusMiles > 0 ? radiusMiles : 100;
        const filtered = (this.allResults || []).filter((r) => (r.distanceMiles ?? 0) <= effectiveRadius);

        const listResults = filtered.slice(0, FindNearestFacilities.LIST_RESULT_LIMIT);
        const markerResults = filtered.slice(0, FindNearestFacilities.MAP_MARKER_LIMIT);

        this.results = listResults;
        this.updateMap(markerResults);
    }

    handleFind() {
        this.executeSearch({ showToastOnSuccess: true });
    }

    getErrorMessage(error) {
        // Handles common Salesforce error shapes (Apex, LDS, network)
        if (!error) return 'Unknown error';
        if (Array.isArray(error)) {
            const msgs = error.map((e) => this.getErrorMessage(e)).filter(Boolean);
            return msgs.length ? msgs.join(', ') : 'Unknown error';
        }
        if (typeof error === 'string') return error;
        // Native JS errors
        if (error instanceof Error && error.message) return error.message;
        if (error?.body) {
            if (typeof error.body === 'string') return error.body;
            if (Array.isArray(error.body)) {
                const msgs = error.body.map((e) => e?.message).filter(Boolean);
                if (msgs.length) return msgs.join(', ');
            }
            if (error.body?.message) return error.body.message;
            if (error.body?.exceptionMessage) return error.body.exceptionMessage;
            if (error.body?.error) return error.body.error;
            // UI API / Apex sometimes nests errors under output
            if (error.body?.output?.errors?.length) {
                const msgs = error.body.output.errors.map((e) => e?.message).filter(Boolean);
                if (msgs.length) return msgs.join(', ');
            }
            if (error.body?.output?.fieldErrors) {
                const fieldMsgs = Object.values(error.body.output.fieldErrors)
                    .flat()
                    .map((e) => e?.message)
                    .filter(Boolean);
                if (fieldMsgs.length) return fieldMsgs.join(', ');
            }
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
        if (error?.statusText) return error.statusText;
        if (error?.status) return `Request failed (${error.status})`;
        try {
            // Try to extract something readable without blowing up on circular refs.
            return JSON.stringify(error, Object.getOwnPropertyNames(error));
        } catch (e) {
            // Last resort: stringify via toString()
            try {
                const s = String(error);
                return s && s !== '[object Object]' ? s : 'Unknown error';
            } catch (e2) {
                return 'Unknown error';
            }
        }
    }

    getErrorDetails(error) {
        const parts = [];
        try {
            parts.push(`type: ${typeof error}`);
            parts.push(`string: ${String(error)}`);
        } catch (e) {
            // ignore
        }
        try {
            const keys = error ? Object.keys(error) : [];
            parts.push(`keys: ${keys.join(', ') || '(none)'}`);
        } catch (e) {
            parts.push('keys: (unavailable)');
        }
        try {
            if (error?.status !== undefined) parts.push(`status: ${error.status}`);
            if (error?.statusText) parts.push(`statusText: ${error.statusText}`);
        } catch (e) {
            // ignore
        }
        try {
            parts.push(`body: ${JSON.stringify(error?.body, Object.getOwnPropertyNames(error?.body || {}))}`);
        } catch (e) {
            parts.push('body: (unavailable)');
        }
        return parts.join('\n');
    }

    executeSearch({ showToastOnSuccess }) {
        if (!this.originAddress) {
            this.showToast('Error', 'Please provide an origin address.', 'error');
            return;
        }

        this.isLoading = true;
        this.lastErrorMessage = '';
        this.lastErrorDetails = '';
        const radius = Number(this.selectedDistance);
        // Always warm cache with a 100-mile search once, then filter locally for 5/15/25/100.
        // This prevents extra Apex/callout work on every radius change.
        const warmRadius = 100;
        const payload = {
            accountId: this.recordId,
            originAddress: this.originAddress,
            radiusMiles: warmRadius
        };

        findNearestFacilitiesWithRadius(payload)
            .then((data = []) => {
                const normalized = this.normalizeResults(data);

                this.allResults = normalized;
                this.applyRadiusFilter(isNaN(radius) ? null : radius);
                this.searchHasRun = true;

                if (showToastOnSuccess) {
                    if (this.results.length) {
                        this.showToast('Success', 'Nearest facilities found successfully.', 'success');
                    } else {
                        this.showToast('Info', 'No facilities found within the selected distance.', 'info');
                    }
                }
            })
            .catch((error) => {
                // eslint-disable-next-line no-console
                console.error('Error finding facilities:', error);
                const msg = this.getErrorMessage(error);
                this.lastErrorMessage = msg;
                this.lastErrorDetails = this.getErrorDetails(error);
                this.showToast('Error', msg, 'error');
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
                description: result.info,
                address: result.address
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

    getGoogleMapsDirectionsUrl(destinationAddress) {
        if (!destinationAddress) return null;
        const origin = this.originAddress ? `&origin=${encodeURIComponent(this.originAddress)}` : '';
        return `https://www.google.com/maps/dir/?api=1${origin}&destination=${encodeURIComponent(destinationAddress)}`;
    }

    handleMarkerSelect(event) {
        const selectedValue = event?.detail?.selectedMarkerValue;
        if (!selectedValue || !this.mapMarkers?.length) return;

        const marker = this.mapMarkers.find((m) => m.value === selectedValue);
        const address = marker?.address;
        const url = this.getGoogleMapsDirectionsUrl(address);
        if (url) window.open(url, '_blank');
    }
}
