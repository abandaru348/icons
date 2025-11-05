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
        const activeStyle = '--sds-c-icon-color-foreground-default: #4b0b1e; --lwc-colorTextIconDefault: #4b0b1e; --sds-c-icon-color-background: #f9e6ef; --lwc-colorBackgroundIcon: #f9e6ef;';
        const disabledStyle = '--sds-c-icon-color-foreground-default: #9a7c89; --lwc-colorTextIconDefault: #9a7c89; --sds-c-icon-color-background: #f4dbe5; --lwc-colorBackgroundIcon: #f4dbe5;';
        return this.appointments.map((a) => ({
            key: a.id,
            label: a.title,
            url: a.url,
            subText: a.subTitle,
            icon: 'standard:note',
            iconClass: 'gnal-icon--appointment',
            iconStyle: activeStyle,
            iconStyleDisabled: disabledStyle,
            rightText: a.dateLabel,
            ariaLabel: `Open appointment ${a.title} on ${a.dateLabel}`
        }));
    }
}
