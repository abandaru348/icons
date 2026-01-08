import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { decodeDefaultFieldValues } from 'lightning/pageReferenceUtils';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import Toast from 'lightning/toast';

import findNearestFacilitiesWithRadius from '@salesforce/apex/GnalFacilitySearchController.findNearestFacilitiesWithRadius';
import getDefaultCurrentLocationForCase from '@salesforce/apex/GnalLocationServicesController.getDefaultCurrentLocationForCase';
import createOrIncrementLocationService from '@salesforce/apex/GnalLocationServicesController.createOrIncrementLocationService';

export default class FindNearestFacilities extends LightningElement {
    static LIST_RESULT_LIMIT = 8;
    static MAP_MARKER_LIMIT = 5;
    static DEFAULT_SELECTED_DISTANCE_MILES = '15';
    static DEFAULT_FILTER_RADIUS_MILES = 100;
    static WARM_CACHE_RADIUS_MILES = 100;
    // Case is a standard object; its keyprefix is consistently "500" across Salesforce orgs.
    static CASE_KEY_PREFIX = '500';

    _recordId;
    _didInitOrigin = false;

    caseId;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;

        // Aura may pass CaseId here; only accept if it really looks like Case
        if (this.looksLikeCaseId(value)) {
            this.setCaseId(value);
        }
    }

    @wire(CurrentPageReference)
    setPageRef(pr) {
        if (this.caseId) return;

        const state = pr?.state || {};

        // 1) Most reliable: defaultFieldValues contains GNAL_Case__c for related-list New
        try {
            if (state.defaultFieldValues) {
                const decoded = decodeDefaultFieldValues(state.defaultFieldValues);
                const cid = decoded?.GNAL_Case__c || decoded?.Case__c;
                if (this.looksLikeCaseId(cid)) {
                    this.setCaseId(cid);
                    return;
                }
            }
        } catch (e) {
            // Non-blocking: page state shapes vary by navigation entry point, and
            // defaultFieldValues may be missing or malformed. If this fails, we fall back
            // to other caseId detection methods below.
            //
            // We intentionally don't console-log this because it's expected in many flows
            // and would create noisy logs for end users/admins.
        }

        // 2) inContextOfRef (base64 JSON)
        try {
            const cid2 = this.caseIdFromInContextOfRef(state.inContextOfRef);
            if (this.looksLikeCaseId(cid2)) {
                this.setCaseId(cid2);
                return;
            }
        } catch (e) {
            // Non-blocking: inContextOfRef may be absent, not base64, or not JSON depending
            // on how this component is launched. Safe to ignore and keep trying.
            //
            // We intentionally don't console-log this because it's expected in many flows.
        }

        // 3) backgroundContext (string URL)
        try {
            const bg = state.backgroundContext;
            if (bg && typeof bg === "string") {
                const m1 = bg.match(/\/lightning\/r\/Case\/([a-zA-Z0-9]{15,18})/);
                const m2 = bg.match(/\/Case\/([a-zA-Z0-9]{15,18})/);
                const cid3 = m1?.[1] || m2?.[1];
                if (this.looksLikeCaseId(cid3)) {
                    this.setCaseId(cid3);
                }
            }
        } catch (e) {
            // Non-blocking: backgroundContext is optional and format varies; ignore parse errors.
            //
            // We intentionally don't console-log this because it's expected in many flows.
        }
    }

    looksLikeCaseId(id) {
        // CaseId is a 15 or 18 char Salesforce Id, and Case keyprefix is "500".
        // This is safe for production because keyprefixes for standard objects don't vary by org.
        if (typeof id !== 'string') return false;
        const trimmed = id.trim();
        const isSalesforceId = /^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$/.test(trimmed);
        return isSalesforceId && trimmed.startsWith(FindNearestFacilities.CASE_KEY_PREFIX);
    }

    caseIdFromInContextOfRef(inCtx) {
        if (!inCtx || typeof inCtx !== 'string') return null;
        let s = inCtx;
        if (s.startsWith('1.')) s = s.substring(2);
        const decoded = JSON.parse(window.atob(s));
        const rid = decoded?.attributes?.recordId;
        return rid || null;
    }

    setCaseId(id) {
        if (!id || this.caseId === id) return;
        this.caseId = id;

        if (!this._didInitOrigin) {
            this._didInitOrigin = true;
            this.initializeOriginAddressFromCase();
        }
    }

    originAddress = '';
    allResults = [];
    results = [];
    isLoading = false;
    showFinder = true;
    mapMarkers = [];
    mapCenter;
    selectedDistance = FindNearestFacilities.DEFAULT_SELECTED_DISTANCE_MILES;
    noticeTitle = '';
    noticeMessage = '';
    noticeVariant = '';
    searchHasRun = false;
    lastErrorMessage = '';

    get hasNotice() {
        return !!this.noticeMessage;
    }

    get noticeClass() {
        const base = 'slds-m-top_medium slds-notify slds-notify_alert slds-theme_alert-texture';
        const variant = (this.noticeVariant || '').toLowerCase();
        if (variant === 'success') return `${base} slds-theme_success`;
        if (variant === 'warning') return `${base} slds-theme_warning`;
        if (variant === 'error') return `${base} slds-theme_error`;
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

    async initializeOriginAddressFromCase() {
        try {
            if (!this.caseId) return;
            const home = await getDefaultCurrentLocationForCase({ caseId: this.caseId });
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
            const msg = 'Please provide an origin address.';
            this.showToast('Error', msg, 'error');
            return;
        }
        if (!this.caseId) {
            const msg = 'This action must be launched from a Case.';
            this.showToast('Error', msg, 'error');
            return;
        }

        this.isLoading = true;
        this.clearNotice();
        this.searchHasRun = false;

        const radius = Number(this.selectedDistance);

        createOrIncrementLocationService({ caseId: this.caseId, currentLocation: normalizedOrigin })
            .then(() =>
                findNearestFacilitiesWithRadius({
                    accountId: null,
                    originAddress: normalizedOrigin,
                    radiusMiles: FindNearestFacilities.WARM_CACHE_RADIUS_MILES
                })
            )
            .then((data = []) => {
                this.allResults = this.normalizeResults(data);
                this.applyRadiusFilter(isNaN(radius) ? null : radius);
                this.searchHasRun = true;

                const hasAnyResults = this.results.length > 0;
                const title = hasAnyResults ? 'Success' : 'Info';
                const message = hasAnyResults
                    ? 'Nearest facilities found successfully.'
                    : 'No facilities found within the selected distance.';
                const variant = hasAnyResults ? 'success' : 'info';
                this.showToast(title, message, variant);
            })
            .catch((error) => {
                const msg = error?.body?.message || error?.message || 'Error finding facilities.';
                this.lastErrorMessage = msg;
                this.showToast('Error', msg, 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
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

        this.results = filtered.slice(0, FindNearestFacilities.LIST_RESULT_LIMIT);
        this.updateMap(filtered.slice(0, FindNearestFacilities.MAP_MARKER_LIMIT));
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
            title: `Facility ${index + 1}`,
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

    clearNotice() {
        this.noticeTitle = '';
        this.noticeMessage = '';
        this.noticeVariant = '';
    }

    setNotice(title, message, variant) {
        this.noticeTitle = title || '';
        this.noticeMessage = message || '';
        this.noticeVariant = variant || 'info';
    }

    showToast(title, message, variant) {
        // Toast implementation differs by container:
        // - Standard Lightning supports lightning/platformShowToastEvent
        // - Experience sites (LWR) support lightning/toast
        // We try both so the same component works everywhere.
        // We still set inline notice/error-details so the message remains visible on the page.
        const t = title || '';
        const m = message || '';
        const v = variant || 'info';
        try {
            // Preferred for standard Lightning containers.
            this.dispatchEvent(new ShowToastEvent({ title: t, message: m, variant: v }));
            return;
        } catch (e) {
            // ignore and fall back
        }
        try {
            // Preferred for Experience Sites (LWR).
            Toast.show({ label: t, message: m, variant: v });
        } catch (e) {
            // Non-blocking: if toasts aren't available in a given container, fall back to inline notice only.
        }
    }

    handleCancel() {
        this.allResults = [];
        this.results = [];
        this.mapMarkers = [];
        this.mapCenter = undefined;
        this.searchHasRun = false;
        this.selectedDistance = FindNearestFacilities.DEFAULT_SELECTED_DISTANCE_MILES;
        this.lastErrorMessage = '';
        this.clearNotice();
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

