import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { decodeDefaultFieldValues } from 'lightning/pageReferenceUtils';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getDefaultCurrentLocationForCase from '@salesforce/apex/GnalLocationServicesController.getDefaultCurrentLocationForCase';
import createOrIncrementLocationService from '@salesforce/apex/GnalLocationServicesController.createOrIncrementLocationService';
import findNearestFacilitiesWithRadius from '@salesforce/apex/GnalFacilitySearchController.findNearestFacilitiesWithRadius';

export default class GnalLocationServicesFinder extends LightningElement {
    static WARM_CACHE_RADIUS_MILES = 100;
    // Debug logging is intentionally off by default to avoid noisy console output for end users.
    // Flip to true temporarily when troubleshooting navigation context issues.
    static DEBUG = false;

    @api recordId; // Case Id when placed on Case page as an action
    caseId; // may be populated from page reference when launched from related list

    currentLocation = '';
    results = [];
    isLoading = false;

    noticeMessage = '';
    noticeVariant = 'info'; // 'info' | 'success' | 'warning' | 'error'

    @wire(CurrentPageReference)
    setPageRef(pr) {
        // When used as a New override from the related list, GNAL_Case__c may come through defaultFieldValues.
        // This is best-effort; if it fails, we fall back to recordId or manual entry.
        try {
            const defaults = pr?.state?.defaultFieldValues;
            if (defaults && !this.caseId && !this.recordId) {
                const decoded = decodeDefaultFieldValues(defaults);
                const cid = decoded?.GNAL_Case__c || decoded?.Case__c;
                if (this.looksLikeCaseId(cid)) this.caseId = cid;
            }
        } catch (e) {
            // Non-blocking: defaultFieldValues is not guaranteed to exist and may be malformed depending on
            // how the component is launched (action vs related list override vs direct navigation).
            // We can still function via recordId/manual entry, so we intentionally don't hard-fail here.
            //
            // Logging: this can be expected/benign in many flows, so we don't log by default.
            // Enable DEBUG temporarily if you want to inspect failures in the browser console.
            if (GnalLocationServicesFinder.DEBUG) {
                // eslint-disable-next-line no-console
                console.warn('Failed to decode defaultFieldValues for Case context', e);
            }
        }
    }

    connectedCallback() {
        // Prefer recordId when present; otherwise fall back to any caseId resolved from page reference.
        this.caseId = this.recordId || this.caseId;
        this.prefillFromCaseHomeAddress();
    }

    get effectiveCaseId() {
        const cid = this.recordId || this.caseId;
        return this.looksLikeCaseId(cid) ? cid.trim() : null;
    }

    get hasResults() {
        return Array.isArray(this.results) && this.results.length > 0;
    }

    get showInlineNotice() {
        // Use inline notice for non-error informational messages.
        // Errors are shown as toasts.
        return !!this.noticeMessage && (this.noticeVariant || '').toLowerCase() !== 'error';
    }

    get noticeClass() {
        const base = 'slds-m-top_small slds-box slds-theme_alert-texture';
        const v = (this.noticeVariant || '').toLowerCase();
        if (v === 'success') return `${base} slds-theme_success`;
        if (v === 'warning') return `${base} slds-theme_warning`;
        if (v === 'error') return `${base} slds-theme_error`;
        return `${base} slds-theme_info`;
    }

    looksLikeCaseId(id) {
        // Case is a standard object; keyprefix is consistently "500" across orgs.
        return typeof id === 'string' && id.trim().length >= 15 && id.trim().startsWith('500');
    }

    async prefillFromCaseHomeAddress() {
        try {
            if (!this.effectiveCaseId) return;
            const home = await getDefaultCurrentLocationForCase({ caseId: this.effectiveCaseId });
            if (home) this.currentLocation = home;
        } catch (e) {
            // Non-blocking: if prefill fails, user can enter a location manually.
            // Intentionally not shown to the user; this is a convenience feature only.
            if (GnalLocationServicesFinder.DEBUG) {
                // eslint-disable-next-line no-console
                console.warn('Failed to prefill current location from Case home address', e);
            }
        }
    }

    handleLocationChange(event) {
        // Store raw input; normalize/trim only at submit time (handleFind) before calling Apex.
        this.currentLocation = event?.target?.value || '';
    }

    handleFind() {
        const normalized = (this.currentLocation || '').trim();
        this.currentLocation = normalized;

        if (!normalized) {
            this.showToast('Error', 'Please provide a current location.', 'error');
            this.setNotice('', 'error'); // don’t show inline error div
            return;
        }
        if (!this.effectiveCaseId) {
            this.showToast('Error', 'This action must be launched from a Case.', 'error');
            this.setNotice('', 'error');
            return;
        }

        this.isLoading = true;
        this.results = [];
        this.setNotice('', 'info');

        createOrIncrementLocationService({ caseId: this.effectiveCaseId, currentLocation: normalized })
            .then(() =>
                findNearestFacilitiesWithRadius({
                    accountId: null,
                    originAddress: normalized,
                    radiusMiles: GnalLocationServicesFinder.WARM_CACHE_RADIUS_MILES
                })
            )
            .then((data = []) => {
                this.results = this.normalizeResults(data);
                const hasAny = this.results.length > 0;
                if (!hasAny) {
                    this.setNotice('No facilities found within the selected distance.', 'info');
                } else {
                    this.setNotice('', 'success');
                }
            })
            .catch((error) => {
                const msg = error?.body?.message || error?.message || 'Error finding facilities.';
                this.showToast('Error', msg, 'error');
                this.setNotice('', 'error');
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

    setNotice(message, variant) {
        this.noticeMessage = message || '';
        this.noticeVariant = variant || 'info';
    }

    showToast(title, message, variant) {
        // Use toast for errors (Salesforce standard UX). Inline notice is reserved for info.
        try {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: title || '',
                    message: message || '',
                    variant: variant || 'info'
                })
            );
        } catch (e) {
            // Non-blocking: if toasts aren't available in this container, fall back silently.
            if (GnalLocationServicesFinder.DEBUG) {
                // eslint-disable-next-line no-console
                console.warn('Failed to dispatch toast event', e);
            }
        }
    }
}

