import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';


export default class GnalPatientPreLoginPage extends LightningElement {
    // ===== Self-Help Links =====
    selfHelpLinks = [
        { label: 'Symptom Checker', iconName: 'utility:search' },
        { label: 'Other Resources', iconName: 'utility:knowledge_base' },
        { label: 'Location Services', iconName: 'utility:location' },
        { label: 'Patient Education', iconName: 'utility:education' }
    ];

    // ===== Telehealth Links =====
    telehealthLinks = [
        { label: 'Chat', iconName: 'utility:chat' },
        { label: 'Phone', iconName: 'utility:call' },
        { label: 'Video', iconName: 'utility:video' },
        { label: 'Email', iconName: 'utility:email' }
    ];

    // ===== My Military Health Links =====
    militaryLinks = [
        { label: 'Quick Care Connect', iconName: 'utility:record_lookup' },
        { label: 'Self Scheduling', iconName: 'utility:event' }
    ];

    // ===== Navigation Handlers =====
    navigateToUrl(url) {
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: { url }
        });
    }

    handleLogin() {
        this.navigateToUrl('/login');
    }

    handleSignup() {
        this.navigateToUrl('/signup');
    }
}
