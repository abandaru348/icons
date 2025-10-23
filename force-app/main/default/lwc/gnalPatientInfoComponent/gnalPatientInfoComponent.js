/**
 * Patient summary tile with configurable fields.
 */
import { api, LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class GNALPatientInfoComponent extends NavigationMixin(LightningElement) {
  @api cardTitle = 'Patient';
  @api name = 'Melanie Robinson';
  @api dob = '03/25/1980';
  @api gender = 'Female';
  @api dbn = '95643521526';
  @api dodId = '1234567890';
  @api pcmClinic = 'Letterkenny OH Clinic';
  @api pcm = 'Jane Smith';

  get initials(){
    return this.name?.split(' ').map(t=>t[0]).join('').slice(0,2).toUpperCase();
  }

  handleNav(event){
    const url = event.currentTarget?.dataset?.url;
    if(!url){ return; }
    this[NavigationMixin.Navigate]({ type:'standard__webPage', attributes:{ url } });
  }
}
