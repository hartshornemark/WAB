import {AuthenticationRequired,CarrierUnavailable} from "@/domain/models";
import {DensityDenied,DensityConflict,validateDensities} from "@/domain/density-settings";
import type {AuthService} from "@/ports/auth-service";
import type {CarrierRepository} from "@/ports/carrier-repository";
import type {DensityRepository} from "@/ports/density-repository";
export function createDensitySettings(auth:AuthService,carriers:CarrierRepository,repository:DensityRepository){
 async function check(iata:string){if(!await auth.currentUser())throw new AuthenticationRequired();if(!iata||iata.length>32||!await carriers.findAuthorised(iata))throw new CarrierUnavailable();}
 return {async get(iata:string){await check(iata);return repository.get(iata);},async save(iata:string,revision:string,input:unknown){await check(iata);const current=await repository.get(iata);if(!current.canEdit)throw new DensityDenied();if(current.revision!==revision)throw new DensityConflict();return repository.save(iata,revision,validateDensities(input));}};
}
