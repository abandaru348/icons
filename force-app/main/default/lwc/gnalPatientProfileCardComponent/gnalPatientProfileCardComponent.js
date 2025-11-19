import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class GnalPatientProfileCardComponent extends NavigationMixin(LightningElement) {
    @api fullName = 'Melanie R. Robinson';
    @api dob = '03/25/1980';
    @api gender = 'Female';
    @api dbn = '95643521526';
    @api dodId = '1234567890';
    @api pcmClinic = 'Letterkenny OH Clinic';
    @api pmc = 'Jane Smith';

    get initials() {
        const parts = (this.fullName || '').split(' ').filter(Boolean);
        return parts.length >= 2 ? `${parts[0][0]}${parts[parts.length - 1][0]}` : (parts[0] ? parts[0][0] : 'P');
    }

    handleViewProfile() {
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: { url: '#' }
        });
    }
}
