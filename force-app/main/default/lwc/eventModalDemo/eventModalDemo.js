import { LightningElement } from 'lwc';
import IMAGE from '@salesforce/resourceUrl/gnalfam';

export default class EventModalDemo extends LightningElement {
    isOpen = false;
    image = IMAGE;
    desc = 'Are you sailing the high seas and concerned about sleeping well? Do you want to learn sleep fundamentals to enhance your operational readiness? Healthy sleep powers the mind, restores the body, and is essential for cognitive processes. This webinar explores important tips for getting great sleep at sea — how to stay comfortable, get to sleep in a sea environment, and develop a sleep routine. (45 minutes)';

    openModal = () => { this.isOpen = true; };
    handleClose = () => { this.isOpen = false; };
    handleEnroll = () => { /* emit toast or navigate, left to host app */ };
}

