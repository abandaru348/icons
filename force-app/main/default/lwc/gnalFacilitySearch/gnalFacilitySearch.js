import { LightningElement, api } from 'lwc';
import getAccountBillingAddress from '@salesforce/apex/GnalFacilitySearchController.getAccountBillingAddress';
import getLatestCaseOriginAddressForAccount from '@salesforce/apex/GnalFacilitySearchController.getLatestCaseOriginAddressForAccount';
import findNearestFacilitiesWithRadius from '@salesforce/apex/GnalFacilitySearchController.findNearestFacilitiesWithRadius';

export default class FindNearestFacilities extends LightningElement {
    static LIST_RESULT_LIMIT = 8;
    static MAP_MARKER_LIMIT = 5;
    static DEFAULT_SELECTED_DISTANCE_MILES = '15';
    static DEFAULT_FILTER_RADIUS_MILES = 100;
    // Always warm cache with this radius once, then filter locally on distance changes.
    static WARM_CACHE_RADIUS_MILES = 100;

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
    originAddress = '';
    allResults = [];
    results = [];
    isLoading = false;
    showFinder = false;
    mapMarkers = [];
    mapCenter;
    selectedDistance = FindNearestFacilities.DEFAULT_SELECTED_DISTANCE_MILES;
    lastErrorMessage = '';
    lastErrorDetails = '';
    noticeTitle = '';
    noticeMessage = '';
    noticeVariant = ''; // success | info | warning | error
    _noticeTimeoutId;
    searchHasRun = false;

    get hasNotice() {
        return !!this.noticeMessage;
    }

    get noticeClass() {
        const base = 'slds-notify slds-notify_toast slds-theme_alert-texture';
        const variant = (this.noticeVariant || '').toLowerCase();
        if (variant === 'success') return `${base} slds-theme_success`;
        if (variant === 'warning') return `${base} slds-theme_warning`;
        if (variant === 'error') return `${base} slds-theme_error`;
        // default/info
        return `${base} slds-theme_info`;
    }

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
        this.selectedDistance = FindNearestFacilities.DEFAULT_SELECTED_DISTANCE_MILES;
        this.lastErrorMessage = '';
        this.lastErrorDetails = '';
        this.clearNotice();
    }

    handleCloseNotice() {
        this.clearNotice();
    }

    handleAddressChange(event) {
        this.originAddress = (event.target.value || '').trim();
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
        const effectiveRadius =
            radiusMiles && radiusMiles > 0 ? radiusMiles : FindNearestFacilities.DEFAULT_FILTER_RADIUS_MILES;
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
        // This component calls Apex imperatively. The common error shapes are:
        // - `error.body.message` (single Apex exception message)
        // - `error.body` as an array of `{ message }` (multiple Apex errors)
        // - an array of errors (e.g., when a caller aggregates failures and rejects with a list)
        const messages = this.collectErrorMessages(error);
        if (messages.length) {
            return messages.join(', ');
        }
        return 'Unknown error';
    }

    collectErrorMessages(error) {
        if (!error) {
            return [];
        }

        if (Array.isArray(error)) {
            return error.flatMap((e) => this.collectErrorMessages(e)).filter(Boolean);
        }

        if (typeof error === 'string') {
            return [error];
        }

        // Native JS errors (rare here, but possible in client code).
        if (error instanceof Error && error.message) {
            return [error.message];
        }

        const body = error?.body;
        if (body) {
            if (typeof body === 'string') {
                return [body];
            }
            if (Array.isArray(body)) {
                return body.map((e) => e?.message).filter(Boolean);
            }
            if (body.message) {
                return [body.message];
            }
            if (body.exceptionMessage) {
                return [body.exceptionMessage];
            }
        }

        if (error?.message) {
            return [error.message];
        }
        if (error?.statusText) {
            return [error.statusText];
        }
        if (error?.status) {
            return [`Request failed (${error.status})`];
        }

        return [];
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
        const normalizedOrigin = (this.originAddress || '').trim();
        this.originAddress = normalizedOrigin;
        if (!normalizedOrigin) {
            this.lastErrorMessage = 'Please provide an origin address.';
            this.lastErrorDetails = '';
            this.setNotice('Error', this.lastErrorMessage, 'error');
            return;
        }

        this.isLoading = true;
        this.lastErrorMessage = '';
        this.lastErrorDetails = '';
        this.clearNotice();
        this.searchHasRun = false;
        const radius = Number(this.selectedDistance);
        const payload = {
            accountId: this.recordId,
            originAddress: normalizedOrigin,
            radiusMiles: FindNearestFacilities.WARM_CACHE_RADIUS_MILES
        };

        findNearestFacilitiesWithRadius(payload)
            .then((data = []) => {
                const normalized = this.normalizeResults(data);

                this.allResults = normalized;
                this.applyRadiusFilter(isNaN(radius) ? null : radius);
                this.searchHasRun = true;

                if (showToastOnSuccess) {
                    if (this.results.length) {
                        this.setNotice('Success', 'Nearest facilities found successfully.', 'success');
                    } else {
                        this.setNotice('Info', 'No facilities found within the selected distance.', 'info');
                    }
                }
            })
            .catch((error) => {
                // eslint-disable-next-line no-console
                console.error('Error finding facilities:', error);
                const msg = this.getErrorMessage(error);
                this.lastErrorMessage = msg;
                this.lastErrorDetails = this.getErrorDetails(error);
                this.setNotice('Error', msg, 'error');
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

    clearNotice() {
        if (this._noticeTimeoutId) {
            window.clearTimeout(this._noticeTimeoutId);
            this._noticeTimeoutId = undefined;
        }
        this.noticeTitle = '';
        this.noticeMessage = '';
        this.noticeVariant = '';
    }

    setNotice(title, message, variant) {
        if (this._noticeTimeoutId) {
            window.clearTimeout(this._noticeTimeoutId);
            this._noticeTimeoutId = undefined;
        }
        this.noticeTitle = title || '';
        this.noticeMessage = message || '';
        this.noticeVariant = variant || 'info';

        // Auto-dismiss non-error notices to behave like a toast.
        if ((this.noticeVariant || '').toLowerCase() !== 'error') {
            this._noticeTimeoutId = window.setTimeout(() => {
                this.clearNotice();
            }, 3500);
        }
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
