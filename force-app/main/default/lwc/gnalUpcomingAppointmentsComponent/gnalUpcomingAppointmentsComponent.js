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
        const palette = ['#0176D3', '#6F2C91', '#04844B', '#FF9A3C'];

        return this.appointments.map((a, index) => ({
            key: a.id,
            label: a.title,
            url: a.url,
            subText: a.subTitle,
            icon: 'standard:note',
            iconBackground: palette[index % palette.length],
            rightText: a.dateLabel,
            rightIcon: 'utility:chevronright',
            ariaLabel: `Open appointment ${a.title} on ${a.dateLabel}`
        }));
    }
}
