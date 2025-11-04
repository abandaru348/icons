import { LightningElement, api } from 'lwc';

export default class GnalMyMilitaryHealthComponent extends LightningElement {
  @api links = [
    { label: 'Quick Care Connect', url: '#', icon: 'utility:call' },
    { label: 'Self Scheduling',    url: '#', icon: 'utility:event' }
  ];
}
