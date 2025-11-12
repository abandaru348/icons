import { LightningElement } from 'lwc';

const SELF_HELP_ICON_COLORS = ['#0B5CAB', '#6F2C91', '#04844B', '#FF9A3C'];
const TELEHEALTH_ICON_COLORS = ['#0176D3', '#04844B', '#6F2C91', '#FF9A3C'];
const MILITARY_ICON_COLORS = ['#C23934', '#0B5CAB'];

export default class GnalPatientPostLoginPage extends LightningElement {
    selfHelpLinks = [
        { label: 'Symptom Checker', url: '#', iconName: 'utility:search', iconBackground: SELF_HELP_ICON_COLORS[0] },
        { label: 'Other Resources', url: '#', iconName: 'utility:knowledge_base', iconBackground: SELF_HELP_ICON_COLORS[1] },
        { label: 'Location Services', url: '#', iconName: 'utility:location', iconBackground: SELF_HELP_ICON_COLORS[2] },
        { label: 'Patient Education', url: '#', iconName: 'utility:education', iconBackground: SELF_HELP_ICON_COLORS[3] }
    ];

    telehealthLinks = [
        { label: 'Chat', url: '#', iconName: 'utility:chat', iconBackground: TELEHEALTH_ICON_COLORS[0] },
        { label: 'Phone', url: '#', iconName: 'utility:call', iconBackground: TELEHEALTH_ICON_COLORS[1] },
        { label: 'Video', url: '#', iconName: 'utility:video', iconBackground: TELEHEALTH_ICON_COLORS[2] },
        { label: 'Email', url: '#', iconName: 'utility:email', iconBackground: TELEHEALTH_ICON_COLORS[3] }
    ];

    militaryLinks = [
        { label: 'Quick Care Connect', url: '#', iconName: 'utility:record_lookup', iconBackground: MILITARY_ICON_COLORS[0] },
        { label: 'Self Scheduling', url: '#', iconName: 'utility:event', iconBackground: MILITARY_ICON_COLORS[1] }
    ];
}
