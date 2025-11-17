import { LightningElement } from 'lwc';
import isGuest from '@salesforce/user/isGuest';

const ICON_STYLE = Object.freeze({
  iconForegroundColor: '#0B5CAB',
  iconBackgroundColor: '#E5ECFF'
});
const UNAUTHENTICATED_MESSAGE = 'Please sign in to access your patient home page.';

export default class GnalPatientPostLoginPage extends LightningElement {
  isAuthenticated = !isGuest;
  unauthenticatedMessage = UNAUTHENTICATED_MESSAGE;

  selfHelpLinks = [
    { label: 'Symptom Checker', url: '#', iconName: 'utility:search', ...ICON_STYLE },
    { label: 'Other Resources', url: '#', iconName: 'utility:knowledge_base', ...ICON_STYLE },
    { label: 'Location Services', url: '#', iconName: 'utility:location', ...ICON_STYLE },
    { label: 'Patient Education', url: '#', iconName: 'utility:education', ...ICON_STYLE }
  ];

  // ===== Telehealth Links =====
  telehealthLinks = [
    { label: 'Chat', url: '#', iconName: 'utility:chat', ...ICON_STYLE },
    { label: 'Phone', url: '#', iconName: 'utility:call', ...ICON_STYLE },
    { label: 'Video', url: '#', iconName: 'utility:video', ...ICON_STYLE },
    { label: 'Email', url: '#', iconName: 'utility:email', ...ICON_STYLE }
  ];

  // ===== My Military Health Links =====
  militaryLinks = [
    { label: 'Quick Care Connect', url: '#', iconName: 'utility:record_lookup', ...ICON_STYLE },
    { label: 'Self Scheduling', url: '#', iconName: 'utility:event', ...ICON_STYLE }
  ];
}
