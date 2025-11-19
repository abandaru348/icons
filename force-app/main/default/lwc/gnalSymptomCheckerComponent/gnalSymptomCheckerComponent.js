import { LightningElement, api } from 'lwc';

const PRE_LOGIN_ICON_STYLE = Object.freeze({
  iconForegroundColor: '#000000'
});

export default class GnalSymptomCheckerComponent extends LightningElement {
  @api links = [
    {
      label: 'Symptom Checker',
      url: 'https://www.google.com/',
      icon: 'utility:info_alt',
      ...PRE_LOGIN_ICON_STYLE
    },
    { label: 'Other Resources', url: '#', icon: 'utility:apps', ...PRE_LOGIN_ICON_STYLE },
    { label: 'Location Services', url: '#', icon: 'utility:location', ...PRE_LOGIN_ICON_STYLE },
    { label: 'Patient Education', url: '#', icon: 'standard:knowledge', ...PRE_LOGIN_ICON_STYLE }
  ];
}
