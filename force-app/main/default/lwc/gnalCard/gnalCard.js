/**
 * GNALCardWrapperComponent
 * Provides consistent card styling and header for portal tiles.
 */
import { api, LightningElement } from 'lwc';

export default class GNALCardComponent extends LightningElement {
  @api title;
  @api iconName;
  @api showFooter = false;
}
