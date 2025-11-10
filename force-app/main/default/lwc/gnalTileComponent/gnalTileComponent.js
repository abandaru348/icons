import { LightningElement, api } from 'lwc';

export default class GnalTileComponent extends LightningElement {
  @api title;
  @api description;
  @api links = [];
  @api learnMoreUrl;
  @api footerUrl;
  @api footerLabel;
  @api authenticated;
}
