import { LightningElement, api, track } from 'lwc';
import isGuest from '@salesforce/user/isGuest';
/**
 * Component: gnalNetworkReferralsComponent
 * Now delegates rendering and navigation to gnalGenericLinkComponent
 */
export default class GnalNetworkReferralsComponent extends LightningElement {
    @track isAuthenticated = !isGuest;

    @api referrals = [
        {
            id: 'r1',
            title: 'Urgent Care Referral',
            subTitle: 'Dr. Damian Kelinz • WHN Dept. of Dermatology',
            dateLabel: 'Oct 22',
            url: '#'
        },
        {
            id: 'r2',
            title: 'Primary Care Referral',
            subTitle: 'Dr. Jones & Associates',
            dateLabel: 'Nov 1',
            url: '#'
        },
        {
            id: 'r3',
            title: 'Lab Diagnostics Referral',
            subTitle: 'Follow-up Immunization',
            dateLabel: 'Dec 11',
            url: '#'
        }
    ];

    get links() {
        return this.referrals.map((r) => ({
            key: r.id,
            label: r.title,
            url: r.url,
            subText: r.subTitle,
            rightText: r.dateLabel,
            ariaLabel: `Open referral ${r.title} dated ${r.dateLabel}`
        }));
    }
}
