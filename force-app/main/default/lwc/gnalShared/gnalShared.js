/* GNAL Shared helpers: navigation, assets */
import { NavigationMixin } from 'lightning/navigation';

export const ASSETS = {
  banner: '/resource/GNAL_Banner',
};

export class NavHelper extends NavigationMixin(Object) {}

export function navigateToUrl(component, url){
  component[NavigationMixin.Navigate]({
    type: 'standard__webPage',
    attributes: { url }
  });
}
