import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import isGuest from '@salesforce/user/isGuest';
import { loadStyle } from 'lightning/platformResourceLoader';
import ASSETS from '@salesforce/resourceUrl/GNAL_icons';

/**
 * Component: gnalNetworkReferralsComponent
 * ---------------------------------------
 * Shows network referrals and statuses. Clickable only for authenticated users.
 */
export default class GnalNetworkReferralsComponent extends NavigationMixin(LightningElement) {
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

    connectedCallback() {
        loadStyle(this, `${ASSETS}/css/mymh_global.css`);
    }

    get viewReferrals() {
        return this.referrals.map((r) => ({
            ...r,
            ariaLabel: `Open referral ${r.title} dated ${r.dateLabel}`
        }));
    }

    handleItemClick(event) {
        if (!this.isAuthenticated) return;
        const id = event.currentTarget.dataset.id;
        const ref = this.referrals.find((r) => r.id === id);
        if (!ref || !ref.url) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: { url: ref.url }
        });
    }

    handleViewAll() {
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: { url: '#' }
        });
    }
}
