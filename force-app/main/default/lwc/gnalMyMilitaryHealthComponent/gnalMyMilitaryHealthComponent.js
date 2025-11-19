import { LightningElement, api } from 'lwc';

const PRE_LOGIN_ICON_STYLE = Object.freeze({
  iconForegroundColor: '#000000'
});

export default class GnalMyMilitaryHealthComponent extends LightningElement {
  @api links = [
    { label: 'Quick Care Connect', url: '#', icon: 'utility:call', ...PRE_LOGIN_ICON_STYLE },
    { label: 'Self Scheduling', url: '#', icon: 'utility:event', ...PRE_LOGIN_ICON_STYLE }
  ];
}
