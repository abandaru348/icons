import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class GNALMyMilitaryHealthComponent extends NavigationMixin(LightningElement) {
  handleNav(event){
    const url = event.currentTarget?.dataset?.url;
    if(!url){ return; }
    this[NavigationMixin.Navigate]({ type:'standard__webPage', attributes:{ url } });
  }
}
