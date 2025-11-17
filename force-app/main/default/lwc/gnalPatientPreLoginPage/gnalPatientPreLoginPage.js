import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class GnalPatientPreLoginPage extends NavigationMixin(LightningElement) {
    @api loginUrl = '/s/login/';
    @api createAccountUrl;

    get resolvedLoginUrl() {
        return this.normalizeUrl(this.loginUrl);
    }

    get resolvedCreateAccountUrl() {
        return this.normalizeUrl(this.createAccountUrl);
    }

    handleLogin() {
        this.navigateTo(this.resolvedLoginUrl);
    }

    handleCreateAccount() {
        this.navigateTo(this.resolvedCreateAccountUrl);
    }

    navigateTo(url) {
        if (!url) {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: { url }
        });
    }

    normalizeUrl(url) {
        if (typeof url !== 'string' || !url.trim()) {
            return null;
        }

        return url.trim();
    }
}
