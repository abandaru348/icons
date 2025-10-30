import { LightningElement, api } from 'lwc';

export default class GnalMyMilitaryHealthComponent extends LightningElement {
  @api links = [
    { label: 'Quick Care Connect', url: '#', icon: 'https://raw.githubusercontent.com/abandaru348/icons/main/CareCompanion.png' },
    { label: 'Self Scheduling',    url: '#', icon: 'https://raw.githubusercontent.com/abandaru348/icons/main/Self%20Schedule.png' }
  ];
}
