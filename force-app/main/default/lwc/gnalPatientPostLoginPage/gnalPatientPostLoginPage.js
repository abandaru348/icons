import { LightningElement } from 'lwc';

const ICON_STYLES = {
  symptomChecker: { iconColor: '#BA2C48', iconBackgroundColor: '#FCE7EC' },
  otherResources: { iconColor: '#6A60B5', iconBackgroundColor: '#ECEAFD' },
  locationServices: { iconColor: '#2E844A', iconBackgroundColor: '#E6F4EA' },
  patientEducation: { iconColor: '#F28B04', iconBackgroundColor: '#FFF1D6' },
  chat: { iconColor: '#0176D3', iconBackgroundColor: '#E5F4FF' },
  phone: { iconColor: '#0E9C63', iconBackgroundColor: '#DBF5EA' },
  video: { iconColor: '#8B2FBB', iconBackgroundColor: '#F3E8FF' },
  email: { iconColor: '#5A25A9', iconBackgroundColor: '#EEE5FF' },
  quickCareConnect: { iconColor: '#0B5CAB', iconBackgroundColor: '#E5ECFF' },
  selfScheduling: { iconColor: '#F28B04', iconBackgroundColor: '#FFF1D6' }
};

export default class GnalPatientPostLoginPage extends LightningElement {
  selfHelpLinks = [
    {
      label: 'Symptom Checker',
      url: '#',
      iconName: 'utility:search',
      ...ICON_STYLES.symptomChecker
    },
    {
      label: 'Other Resources',
      url: '#',
      iconName: 'utility:knowledge_base',
      ...ICON_STYLES.otherResources
    },
    {
      label: 'Location Services',
      url: '#',
      iconName: 'utility:location',
      ...ICON_STYLES.locationServices
    },
    {
      label: 'Patient Education',
      url: '#',
      iconName: 'utility:education',
      ...ICON_STYLES.patientEducation
    }
  ];

  // ===== Telehealth Links =====
  telehealthLinks = [
    {
      label: 'Chat',
      url: '#',
      iconName: 'utility:chat',
      ...ICON_STYLES.chat
    },
    {
      label: 'Phone',
      url: '#',
      iconName: 'utility:call',
      ...ICON_STYLES.phone
    },
    {
      label: 'Video',
      url: '#',
      iconName: 'utility:video',
      ...ICON_STYLES.video
    },
    {
      label: 'Email',
      url: '#',
      iconName: 'utility:email',
      ...ICON_STYLES.email
    }
  ];

  // ===== My Military Health Links =====
  militaryLinks = [
    {
      label: 'Quick Care Connect',
      url: '#',
      iconName: 'utility:record_lookup',
      ...ICON_STYLES.quickCareConnect
    },
    {
      label: 'Self Scheduling',
      url: '#',
      iconName: 'utility:event',
      ...ICON_STYLES.selfScheduling
    }
  ];
}
