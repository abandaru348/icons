import { LightningElement, api } from 'lwc';

export default class GnalMyMilitaryHealthComponent extends LightningElement {
  @api links = [
    { label: 'Quick Care Connect', url: '#', icon: 'utility:call', iconBackground: '#C23934' },
    { label: 'Self Scheduling', url: '#', icon: 'utility:event', iconBackground: '#0B5CAB' }
  ];
}
