import{AuthenticationRequired,CarrierUnavailable}from"@/domain/models";
import type{AuthService}from"@/ports/auth-service";
import type{CarrierRepository}from"@/ports/carrier-repository";
import type{CarrierLogoRepository}from"@/ports/carrier-logo-repository";
import type{AircraftC1Repository}from"@/ports/aircraft-c1-repository";

export function createCarrierHome(auth:AuthService,carriers:CarrierRepository,logos:CarrierLogoRepository,aircraft:AircraftC1Repository){
  return{async get(iata:string){
    const user=await auth.currentUser();
    if(!user)throw new AuthenticationRequired();
    if(!iata||iata.length>32)throw new CarrierUnavailable();
    const[carrier,branding,list]=await Promise.all([carriers.findAuthorised(iata),logos.getMany([iata]),aircraft.list(iata)]);
    if(!carrier)throw new CarrierUnavailable();
    return{user,carrier:{...carrier,...(branding[iata]?{logoUrl:branding[iata]}:{})},aircraft:list};
  }};
}
