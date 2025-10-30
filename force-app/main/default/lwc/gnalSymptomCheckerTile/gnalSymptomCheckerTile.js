import { LightningElement, api } from 'lwc';

export default class GnalSymptomCheckerTile extends LightningElement {
  @api links = [
    { label: 'Symptom Checker', url: 'https://www.google.com/', icon: 'https://raw.githubusercontent.com/abandaru348/icons/main/Symptom%20Checker.png' },
    { label: 'Other Resources', url: '#', icon: 'https://raw.githubusercontent.com/abandaru348/icons/main/Other%20Resources.png' },
    { label: 'Location Services', url: '#', icon: 'https://raw.githubusercontent.com/abandaru348/icons/main/Location%20Services.png' },
    { label: 'Patient Education', url: '#', icon: 'https://raw.githubusercontent.com/abandaru348/icons/main/Patient%20Education.png' }
  ];
}
