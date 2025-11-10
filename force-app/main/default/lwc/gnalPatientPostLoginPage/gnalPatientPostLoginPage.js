import { LightningElement } from 'lwc';

export default class GnalPatientPostLoginPage extends LightningElement {
  selfHelpLinks = [
    { label: 'Symptom Checker', url: '#', iconName: 'utility:search' },
    { label: 'Other Resources', url: '#', iconName: 'utility:knowledge_base' },
    { label: 'Location Services', url: '#', iconName: 'utility:location' },
    { label: 'Patient Education', url: '#', iconName: 'utility:education' }
  ];

  telehealthLinks = [
    { label: 'Chat', url: '#', iconName: 'utility:chat' },
    { label: 'Phone', url: '#', iconName: 'utility:call' },
    { label: 'Video', url: '#', iconName: 'utility:video' },
    { label: 'Email', url: '#', iconName: 'utility:email' }
  ];

  militaryLinks = [
    { label: 'Quick Care Connect', url: '#', iconName: 'utility:record_lookup' },
    { label: 'Self Scheduling', url: '#', iconName: 'utility:event' }
  ];
}
