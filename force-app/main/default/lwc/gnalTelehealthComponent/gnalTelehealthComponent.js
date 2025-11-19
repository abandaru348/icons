import { LightningElement, api } from 'lwc';

const PRE_LOGIN_ICON_STYLE = Object.freeze({
  iconForegroundColor: '#000000'
});

export default class GnalTelehealthComponent extends LightningElement {
  @api links = [
    { label: 'Chat', url: '#', icon: 'utility:chat', ...PRE_LOGIN_ICON_STYLE },
    { label: 'Video', url: '#', icon: 'utility:video', ...PRE_LOGIN_ICON_STYLE },
    { label: 'Phone', url: '#', icon: 'utility:call', ...PRE_LOGIN_ICON_STYLE },
    { label: 'Email', url: '#', icon: 'utility:email', ...PRE_LOGIN_ICON_STYLE }
  ];
}
