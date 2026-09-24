import{AuthenticationRequired,CarrierUnavailable}from"@/domain/models";
import{AircraftC1Denied,AircraftC1Conflict,validateC1,validateIdentity,validateManufacturerAssignment,validateVariantCodes}from"@/domain/aircraft-c1";
import type{AuthService}from"@/ports/auth-service";
import type{CarrierRepository}from"@/ports/carrier-repository";
import type{AircraftC1Repository}from"@/ports/aircraft-c1-repository";

export function createAircraftC1(auth:AuthService,carriers:CarrierRepository,repo:AircraftC1Repository){
  async function check(iata:string){if(!await auth.currentUser())throw new AuthenticationRequired();if(!iata||!await carriers.findAuthorised(iata))throw new CarrierUnavailable();}
  return{
    async list(iata:string){await check(iata);return repo.list(iata);},
    async get(iata:string,typeCode:string,subtype:string){await check(iata);return repo.get(iata,typeCode,subtype);},
    async searchIdentities(query:string){if(!await auth.currentUser())throw new AuthenticationRequired();return query.trim().length<2?[]:repo.searchIdentities(query.trim());},
    async searchManufacturers(query:string){if(!await auth.currentUser())throw new AuthenticationRequired();return query.trim().length<2?[]:repo.searchManufacturers(query.trim());},
    async createIdentity(input:unknown){if(!await auth.currentUser())throw new AuthenticationRequired();return repo.createIdentity(validateIdentity(input));},
    async save(iata:string,typeCode:string,subtype:string,revision:string,input:unknown){
      await check(iata);
      const current=await repo.get(iata,typeCode,subtype);
      if(!current.canEdit)throw new AircraftC1Denied();
      if(current.revision!==revision)throw new AircraftC1Conflict();
      const clean=validateC1(input);
      const variantCodes=validateVariantCodes((input as Record<string,unknown>)?.variantCodes,current.subtype);
      const manufacturerId=validateManufacturerAssignment((input as Record<string,unknown>)?.manufacturerId);
      if(manufacturerId&&!current.manufacturerId){
        if(!current.canAssignManufacturer)throw new AircraftC1Denied();
        await repo.assignManufacturer(typeCode,subtype,manufacturerId);
      }
      return repo.save(iata,typeCode,subtype,revision,clean.aircraftName,variantCodes,clean.operatingRole,clean.values);
    }
  };
}
