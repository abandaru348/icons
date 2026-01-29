import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import Toast from 'lightning/toast';

import findNearestFacilitiesWithRadius from '@salesforce/apex/GnalFacilitySearchController.findNearestFacilitiesWithRadius';
import getDefaultCurrentLocationForPortalUser from '@salesforce/apex/GnalLocationServicesController.getDefaultCurrentLocationForPortalUser';
import createPortalCaseAndLocationService from '@salesforce/apex/GnalLocationServicesController.createPortalCaseAndLocationService';
import createOrIncrementLocationServiceIfResults from '@salesforce/apex/GnalLocationServicesController.createOrIncrementLocationServiceIfResults';

export default class GnalFacilitySearchPortal extends LightningElement {
    static LIST_PAGE_SIZE = 10;
    static MAP_MARKER_LIMIT = 10;
    static DEFAULT_SELECTED_DISTANCE_MILES = '5';
    static DEFAULT_FILTER_RADIUS_MILES = 100;
    static WARM_CACHE_RADIUS_MILES = 100;

    originAddress = '';
    allResults = [];
    filteredResults = [];
    pageResults = [];
    mapMarkers = [];
    mapCenter;
    selectedDistance = GnalFacilitySearchPortal.DEFAULT_SELECTED_DISTANCE_MILES;
    isLoading = false;
    searchHasRun = false;
    currentPage = 1;
    activeView = 'list';
    lastCaseId;

    connectedCallback() {
        this.initializeOriginAddressFromUser();
    }

    async initializeOriginAddressFromUser() {
        try {
            const home = await getDefaultCurrentLocationForPortalUser();
            if (home) this.originAddress = home;
        } catch (e) {
            // leave blank if cannot prefill
        }
    }

    handleAddressChange(event) {
        this.originAddress = (event.target.value || '').trim();
    }

    handleDistanceChange(event) {
        this.selectedDistance = event.detail.value;
        if (!this.searchHasRun || this.isLoading) return;
        const radius = Number(this.selectedDistance);
        this.applyRadiusFilter(isNaN(radius) ? null : radius);
    }

    handleFind() {
        const normalizedOrigin = (this.originAddress || '').trim();
        this.originAddress = normalizedOrigin;

        if (!normalizedOrigin) {
            this.showToast('Error', 'Please provide an origin address.', 'error');
            return;
        }

        this.isLoading = true;
        this.searchHasRun = false;
        this.currentPage = 1;

        const radius = Number(this.selectedDistance);

        findNearestFacilitiesWithRadius({
            accountId: null,
            originAddress: normalizedOrigin,
            radiusMiles: GnalFacilitySearchPortal.WARM_CACHE_RADIUS_MILES
        })
            .then((data = []) => {
                this.allResults = this.normalizeResults(data);
                this.applyRadiusFilter(isNaN(radius) ? null : radius);
                this.searchHasRun = true;

                const hasAnyResults = this.filteredResults.length > 0;
                const title = hasAnyResults ? 'Success' : 'Info';
                const message = hasAnyResults
                    ? 'Nearest facilities found successfully.'
                    : 'No facilities found within the selected distance.';
                const variant = hasAnyResults ? 'success' : 'info';
                this.showToast(title, message, variant);

                if (this.lastCaseId) {
                    return createOrIncrementLocationServiceIfResults({
                        caseId: this.lastCaseId,
                        currentLocation: normalizedOrigin,
                        resultCount: this.filteredResults.length
                    }).then(() => ({ caseId: this.lastCaseId }));
                }
                return createPortalCaseAndLocationService({
                    currentLocation: normalizedOrigin,
                    resultCount: this.filteredResults.length
                });
            })
            .then((result) => {
                this.lastCaseId = result?.caseId;
            })
            .catch((error) => {
                const msg = error?.body?.message || error?.message || 'Error finding facilities.';
                this.showToast('Error', msg, 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleClear() {
        this.allResults = [];
        this.filteredResults = [];
        this.pageResults = [];
        this.mapMarkers = [];
        this.mapCenter = undefined;
        this.searchHasRun = false;
        this.currentPage = 1;
    }

    handlePrevPage() {
        if (this.isPrevDisabled) return;
        this.currentPage -= 1;
        this.updatePageResults();
    }

    handleNextPage() {
        if (this.isNextDisabled) return;
        this.currentPage += 1;
        this.updatePageResults();
    }

    handleViewToggle(event) {
        const view = event?.currentTarget?.dataset?.view;
        if (view === 'list' || view === 'map') {
            this.activeView = view;
        }
    }

    get distanceOptions() {
        return [
            { label: '5 miles', value: '5' },
            { label: '15 miles', value: '15' },
            { label: '25 miles', value: '25' },
            { label: '100 miles', value: '100' }
        ];
    }

    get hasResults() {
        return this.filteredResults && this.filteredResults.length > 0;
    }

    get showingCountText() {
        if (!this.searchHasRun) return '';
        const total = this.totalResults;
        if (total <= 0) return 'Showing 0 Locations';
        return `Showing ${this.startIndex} to ${this.endIndex} of ${total} Locations`;
    }

    get totalResults() {
        return this.filteredResults ? this.filteredResults.length : 0;
    }

    get startIndex() {
        if (this.totalResults === 0) return 0;
        return (this.currentPage - 1) * GnalFacilitySearchPortal.LIST_PAGE_SIZE + 1;
    }

    get endIndex() {
        if (this.totalResults === 0) return 0;
        const end = this.currentPage * GnalFacilitySearchPortal.LIST_PAGE_SIZE;
        return end > this.totalResults ? this.totalResults : end;
    }

    get isPrevDisabled() {
        return this.currentPage <= 1;
    }

    get isNextDisabled() {
        return this.currentPage >= this.totalPages;
    }

    get totalPages() {
        if (this.totalResults <= 0) return 1;
        return Math.ceil(this.totalResults / GnalFacilitySearchPortal.LIST_PAGE_SIZE);
    }

    get listButtonVariant() {
        return this.activeView === 'list' ? 'brand' : 'neutral';
    }

    get mapButtonVariant() {
        return this.activeView === 'map' ? 'brand' : 'neutral';
    }

    get listContainerClass() {
        return `portal-list ${this.activeView === 'list' ? '' : 'is-hidden'}`;
    }

    get mapContainerClass() {
        return `portal-map ${this.activeView === 'map' ? '' : 'is-hidden'}`;
    }

    normalizeResults(data = []) {
        return (data || []).map((r) => {
            const minutesNum = Number(r?.minutes ?? 0);
            const milesNum = Number(r?.distanceMiles ?? 0);
            const safeMinutes = Number.isFinite(minutesNum) ? minutesNum : 0;
            const safeMiles = Number.isFinite(milesNum) ? milesNum : 0;

            const address = typeof r?.address === 'string' ? r.address : '';
            const facilityName = typeof r?.facilityName === 'string' ? r.facilityName : '';
            const displayName = facilityName ? facilityName : address;
            const displayAddress = facilityName ? address : null;

            return {
                ...r,
                address,
                facilityName,
                displayName,
                displayAddress,
                minutes: safeMinutes,
                distanceMiles: safeMiles,
                info: `${safeMiles.toFixed(1)} miles  ${Math.round(safeMinutes)} min`
            };
        });
    }

    applyRadiusFilter(radiusMiles) {
        const effectiveRadius =
            radiusMiles && radiusMiles > 0 ? radiusMiles : GnalFacilitySearchPortal.DEFAULT_FILTER_RADIUS_MILES;

        this.filteredResults = (this.allResults || []).filter((r) => (r.distanceMiles ?? 0) <= effectiveRadius);
        this.currentPage = 1;
        this.updatePageResults();
    }

    updatePageResults() {
        const start = (this.currentPage - 1) * GnalFacilitySearchPortal.LIST_PAGE_SIZE;
        const end = start + GnalFacilitySearchPortal.LIST_PAGE_SIZE;
        const slice = (this.filteredResults || []).slice(start, end);
        this.pageResults = slice.map((r, index) => ({
            ...r,
            displayIndex: start + index + 1,
            directionsUrl: this.getGoogleMapsDirectionsUrl(r.address)
        }));
        this.updateMap(this.pageResults.slice(0, GnalFacilitySearchPortal.MAP_MARKER_LIMIT));
    }

    updateMap(resultsForMap) {
        if (!resultsForMap || !resultsForMap.length) {
            this.mapMarkers = [];
            this.mapCenter = undefined;
            return;
        }

        const markers = resultsForMap.map((result, index) => ({
            location:
                result.latitude != null && result.longitude != null
                    ? { Latitude: result.latitude, Longitude: result.longitude }
                    : { Street: result.address },
            value: `${result.address}-${index}`,
            title: result.displayName || `Facility ${index + 1}`,
            description: result.info,
            address: result.address
        }));

        this.mapMarkers = markers;

        const firstWithCoords = markers.find(
            (m) => m.location.Latitude !== undefined && m.location.Longitude !== undefined
        );
        this.mapCenter = firstWithCoords
            ? { location: { Latitude: firstWithCoords.location.Latitude, Longitude: firstWithCoords.location.Longitude } }
            : undefined;
    }

    handleMarkerSelect(event) {
        const selectedValue = event?.detail?.selectedMarkerValue;
        if (!selectedValue || !this.mapMarkers?.length) return;
        const marker = this.mapMarkers.find((m) => m.value === selectedValue);
        const address = marker?.address;
        const url = this.getGoogleMapsDirectionsUrl(address);
        if (url) window.open(url, '_blank');
    }

    showToast(title, message, variant) {
        const toastTitle = title || '';
        const toastMessage = message || '';
        const toastVariant = variant || 'info';
        try {
            this.dispatchEvent(new ShowToastEvent({ title: toastTitle, message: toastMessage, variant: toastVariant }));
            return;
        } catch (error) {
            // ignore and fall back
        }
        try {
            Toast.show({ label: toastTitle, message: toastMessage, variant: toastVariant });
        } catch (error) {
            // Non-blocking: if toasts aren't available, do nothing.
        }
    }

    getGoogleMapsDirectionsUrl(destinationAddress) {
        if (!destinationAddress) return null;
        const origin = this.originAddress ? `&origin=${encodeURIComponent(this.originAddress)}` : '';
        return `https://www.google.com/maps/dir/?api=1${origin}&destination=${encodeURIComponent(destinationAddress)}`;
    }
}
