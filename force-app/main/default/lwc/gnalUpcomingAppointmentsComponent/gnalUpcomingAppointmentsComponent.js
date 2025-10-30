import { LightningElement, api, track } from 'lwc';
import isGuest from '@salesforce/user/isGuest';
/**
 * Component: gnalUpcomingAppointmentsComponent
 * Now delegates rendering and navigation to gnalGenericLinkComponent
 */
export default class GnalUpcomingAppointmentsComponent extends LightningElement {
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

    get links() {
        return this.appointments.map((a) => ({
            key: a.id,
            label: a.title,
            url: a.url,
            rightText: a.dateLabel,
            ariaLabel: `Open appointment ${a.title} on ${a.dateLabel}`
        }));
    }
}
