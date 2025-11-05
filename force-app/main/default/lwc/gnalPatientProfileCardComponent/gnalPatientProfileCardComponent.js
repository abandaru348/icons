import { LightningElement, api } from 'lwc';

export default class GnalPatientProfileCardComponent extends LightningElement {
    @api fullName = 'Melanie R. Robinson';
    @api dob = '03/25/1980';
    @api gender = 'Female';
    @api dbn = '95643521526';
    @api dodId = '1234567890';
    @api pcmClinic = 'Letterkenny OH Clinic';
    @api pmc = 'Jane Smith';
    @api profileUrl = '#';

    get initials() {
        const parts = (this.fullName || '').split(' ').filter(Boolean);
        return parts.length >= 2 ? `${parts[0][0]}${parts[parts.length - 1][0]}` : (parts[0] ? parts[0][0] : 'P');
    }

    get profileLinks() {
        return [
            {
                key: 'dob',
                label: this.dob,
                subText: 'Date of Birth',
                rightText: this.gender ? `Gender: ${this.gender}` : null
            },
            {
                key: 'dbn',
                label: this.dbn,
                subText: 'DBN',
                rightText: this.dodId ? `DoD ID #: ${this.dodId}` : null
            },
            {
                key: 'pcm',
                label: this.pcmClinic,
                subText: 'PCM Clinic',
                rightText: this.pmc ? `PMC: ${this.pmc}` : null
            }
        ];
    }

    get headerSummary() {
        const summaryParts = [
            this.dbn ? `DBN ${this.dbn}` : null,
            this.dodId ? `DoD ID # ${this.dodId}` : null
        ].filter(Boolean);
        return summaryParts.join(' • ');
    }
}
