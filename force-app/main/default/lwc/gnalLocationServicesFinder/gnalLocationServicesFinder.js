import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getDefaultCurrentLocationForCase from '@salesforce/apex/GnalLocationServicesController.getDefaultCurrentLocationForCase';
import createOrIncrementLocationService from '@salesforce/apex/GnalLocationServicesController.createOrIncrementLocationService';
import findNearestFacilitiesWithRadius from '@salesforce/apex/GnalFacilitySearchController.findNearestFacilitiesWithRadius';

export default class GnalLocationServicesFinder extends LightningElement {
    static DEFAULT_RADIUS_MILES = 100;

    @api recordId; // expected to be Case Id when placed on a Case record page

    currentLocation = '';
    results = [];
    isLoading = false;

    noticeMessage = '';
    noticeVariant = 'info'; // 'info' | 'success' | 'warning' | 'error'

    connectedCallback() {
        this.prefillFromCaseHomeAddress();
    }

    get caseId() {
        return this.looksLikeCaseId(this.recordId) ? this.recordId : null;
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
            if (!this.caseId) return;
            const home = await getDefaultCurrentLocationForCase({ caseId: this.caseId });
            if (home) this.currentLocation = home;
        } catch (e) {
            // Non-blocking: if prefill fails, user can enter a location manually.
        }
    }

    handleLocationChange(event) {
        // Keep UI state clean, but still re-trim at submit as defense-in-depth.
        this.currentLocation = (event?.target?.value || '').trim();
    }

    handleFind() {
        const normalized = (this.currentLocation || '').trim();
        this.currentLocation = normalized;

        if (!normalized) {
            this.showToast('Error', 'Please provide a current location.', 'error');
            this.setNotice('', 'error'); // don’t show inline error div
            return;
        }
        if (!this.caseId) {
            this.showToast('Error', 'This action must be launched from a Case.', 'error');
            this.setNotice('', 'error');
            return;
        }

        this.isLoading = true;
        this.results = [];
        this.setNotice('', 'info');

        createOrIncrementLocationService({ caseId: this.caseId, currentLocation: normalized })
            .then(() =>
                findNearestFacilitiesWithRadius({
                    accountId: null,
                    originAddress: normalized,
                    radiusMiles: GnalLocationServicesFinder.DEFAULT_RADIUS_MILES
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
        }
    }
}

