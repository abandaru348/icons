import { LightningElement, api } from 'lwc';

export default class GnalSymptomCheckerComponent extends LightningElement {
  @api links = [
    { label: 'Symptom Checker', url: 'https://www.google.com/', icon: 'utility:info_alt', iconBackground: '#0B5CAB' },
    { label: 'Other Resources', url: '#', icon: 'utility:apps', iconBackground: '#6F2C91' },
    { label: 'Location Services', url: '#', icon: 'utility:location', iconBackground: '#04844B' },
    { label: 'Patient Education', url: '#', icon: 'standard:knowledge', iconBackground: '#FF9A3C' }
  ];
}
