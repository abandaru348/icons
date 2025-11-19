import { LightningElement } from 'lwc';
import isGuest from '@salesforce/user/isGuest';

export default class GnalPatientPostLoginPage extends LightningElement {
  isAuthenticated = !isGuest;

  selfHelpLinks = [
    { label: 'Symptom Checker', url: '#', iconName: 'utility:search' },
    { label: 'Other Resources', url: '#', iconName: 'utility:knowledge_base' },
    { label: 'Location Services', url: '#', iconName: 'utility:location' },
    { label: 'Patient Education', url: '#', iconName: 'utility:education' }
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
}
