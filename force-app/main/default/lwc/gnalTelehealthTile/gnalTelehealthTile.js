import { LightningElement, api } from 'lwc';

export default class GnalTelehealthTile extends LightningElement {
  @api links = [
    { label: 'Chat',  url: '#', icon: 'https://raw.githubusercontent.com/abandaru348/icons/main/Chat.png' },
    { label: 'Video', url: '#', icon: 'https://raw.githubusercontent.com/abandaru348/icons/main/Video.png' },
    { label: 'Phone', url: '#', icon: 'https://raw.githubusercontent.com/abandaru348/icons/main/Phone.png' },
    { label: 'Email', url: '#', icon: 'https://raw.githubusercontent.com/abandaru348/icons/main/Email.png' }
  ];
}
