import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

const PRE_LOGIN_ICON_STYLE = Object.freeze({
    iconForegroundColor: '#000000'
});

const toPreLoginLinks = (links) =>
    links.map((link) => ({
        ...link,
        url: null,
        ...PRE_LOGIN_ICON_STYLE
    }));

const SELF_HELP_LINKS = toPreLoginLinks([
    { label: 'Symptom Checker', iconName: 'utility:search' },
    { label: 'Other Resources', iconName: 'utility:knowledge_base' },
    { label: 'Location Services', iconName: 'utility:location' },
    { label: 'Patient Education', iconName: 'utility:education' }
]);

const TELEHEALTH_LINKS = toPreLoginLinks([
    { label: 'Chat', iconName: 'utility:chat' },
    { label: 'Phone', iconName: 'utility:call' },
    { label: 'Video', iconName: 'utility:video' },
    { label: 'Email', iconName: 'utility:email' }
]);

const MILITARY_LINKS = toPreLoginLinks([
    { label: 'Quick Care Connect', iconName: 'utility:record_lookup' },
    { label: 'Self Scheduling', iconName: 'utility:event' }
]);

export default class GnalPatientPreLoginPage extends NavigationMixin(LightningElement) {
    @api loginUrl = '/s/login/';
    @api createAccountUrl;

    selfHelpLinks = SELF_HELP_LINKS;
    telehealthLinks = TELEHEALTH_LINKS;
    militaryLinks = MILITARY_LINKS;

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
