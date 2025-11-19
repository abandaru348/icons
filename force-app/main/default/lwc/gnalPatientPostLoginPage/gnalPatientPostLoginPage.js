import { LightningElement } from 'lwc';
import isGuest from '@salesforce/user/isGuest';

export default class GnalPatientPostLoginPage extends LightningElement {
  isAuthenticated = !isGuest;

   selfHelpLinks = [
        { label: 'Symptom Checker', url: '/gnal-symptom-checker', iconName: 'utility:search' },
        { label: 'Other Resources', url: '/gnal-other-resources', iconName: 'utility:knowledge_base' },
        { label: 'Location Services', url: '/gnal-location-services', iconName: 'utility:location' },
        { label: 'Patient Education', url: '/gnal-patient-education', iconName: 'utility:education' }
  ];
    
     // ===== Telehealth Links =====
    telehealthLinks = [
        { label: 'Chat', url: '#', iconName: 'utility:chat' },
        { label: 'Phone', url: '#', iconName: 'utility:call' },
        { label: 'Video', url: '#', iconName: 'utility:video' },
        { label: 'Email', url: '#', iconName: 'utility:email' }
    ];

    // ===== My Military Health Links =====
    militaryLinks = [
        { label: 'Quick Care Connect', url: '#', iconName: 'utility:record_lookup' },
        { label: 'Self Scheduling', url: '#', iconName: 'utility:event' }
        
        
    ];
    
}
