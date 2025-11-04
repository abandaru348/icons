import { LightningElement, api } from 'lwc';

export default class GnalSymptomCheckerComponent extends LightningElement {
  @api links = [
    { label: 'Symptom Checker', url: 'https://www.google.com/', icon: 'utility:info_alt' },
    { label: 'Other Resources', url: '#', icon: 'utility:apps' },
    { label: 'Location Services', url: '#', icon: 'utility:location' },
    { label: 'Patient Education', url: '#', icon: 'standard:knowledge' }
  ];
}
