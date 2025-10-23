import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class GnalSymptomCheckerComponent extends NavigationMixin(LightningElement) {
  handleNav(event){
    const url = event.currentTarget?.dataset?.url;
    if(!url){ return; }
    this[NavigationMixin.Navigate]({ type:'standard__webPage', attributes:{ url } });
  }
}
