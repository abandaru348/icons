import { LightningElement, api } from 'lwc';

export default class GnalTelehealthComponent extends LightningElement {
  @api links = [
    { label: 'Chat',  url: '#', icon: 'utility:chat' },
    { label: 'Video', url: '#', icon: 'utility:video' },
    { label: 'Phone', url: '#', icon: 'utility:call' },
    { label: 'Email', url: '#', icon: 'utility:email' }
  ];
}
