import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import isGuest from '@salesforce/user/isGuest';
import { loadStyle } from 'lightning/platformResourceLoader';
import ASSETS from '@salesforce/resourceUrl/mymh_assets';

/**
 * Component: gnalUpcomingAppointmentsComponent
 * -------------------------------------------
 * Renders a list of upcoming appointments similar to the UI mock.
 * Items are clickable only for authenticated users.
 */
export default class GnalUpcomingAppointmentsComponent extends NavigationMixin(LightningElement) {
    @track isAuthenticated = !isGuest;

    @api appointments = [
        {
            id: '1',
            title: 'Dr. Ragu Patel',
            subTitle: 'Dermatology • WHN Dept. of Dermatology',
            dateLabel: 'Oct 22',
            url: '#'
        },
        {
            id: '2',
            title: 'Dr. Kristen Jones',
            subTitle: 'Internal Medicine • Dr. Jones & Associates',
            dateLabel: 'Nov 1',
            url: '#'
        },
        {
            id: '3',
            title: 'Lab Diagnostics',
            subTitle: 'Immunization',
            dateLabel: 'Dec 11',
            url: '#'
        }
    ];

    connectedCallback() {
        loadStyle(this, `${ASSETS}/css/mymh_global.css`);
    }

    get viewAppointments() {
        return this.appointments.map((a) => ({
            ...a,
            ariaLabel: `Open appointment ${a.title} on ${a.dateLabel}`
        }));
    }

    handleItemClick(event) {
        if (!this.isAuthenticated) return;
        const id = event.currentTarget.dataset.id;
        const appt = this.appointments.find((a) => a.id === id);
        if (!appt || !appt.url) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: { url: appt.url }
        });
    }

    handleViewAll() {
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: { url: '#' }
        });
    }
}
