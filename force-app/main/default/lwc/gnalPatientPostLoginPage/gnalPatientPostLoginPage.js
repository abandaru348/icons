import { LightningElement } from 'lwc';

export default class GnalPatientPostLoginPage extends LightningElement {
    selfHelpLinks = [
        { label: 'Symptom Checker', url: 'https://www.google.com/', icon: 'utility:info_alt' },
        { label: 'Other Resources', url: '#', icon: 'utility:apps' },
        { label: 'Location Services', url: '#', icon: 'utility:location' },
        { label: 'Patient Education', url: '#', icon: 'standard:knowledge' }
    ];

    telehealthLinks = [
        { label: 'Chat', url: '#', icon: 'utility:chat' },
        { label: 'Phone', url: '#', icon: 'utility:call' },
        { label: 'Video', url: '#', icon: 'utility:video' },
        { label: 'Email', url: '#', icon: 'utility:email' }
    ];

    militaryLinks = [
        { label: 'Quick Care Connect', url: '#', icon: 'utility:call' },
        { label: 'Self Scheduling', url: '#', icon: 'utility:event' }
    ];
}
