import { LightningElement, api } from 'lwc';

export default class GnalTelehealthComponent extends LightningElement {
  @api links = [
    { label: 'Chat', url: '#', icon: 'utility:chat', iconBackground: '#0176D3' },
    { label: 'Video', url: '#', icon: 'utility:video', iconBackground: '#6F2C91' },
    { label: 'Phone', url: '#', icon: 'utility:call', iconBackground: '#04844B' },
    { label: 'Email', url: '#', icon: 'utility:email', iconBackground: '#FF9A3C' }
  ];
}
