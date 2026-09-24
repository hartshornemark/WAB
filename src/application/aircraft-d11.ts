import { AuthenticationRequired, CarrierUnavailable } from "@/domain/models";
import { AircraftD11Conflict, AircraftD11Denied, AircraftD11Invalid, validateD11FloorLimits } from "@/domain/aircraft-d11";
import type { AuthService } from "@/ports/auth-service";
import type { CarrierRepository } from "@/ports/carrier-repository";
import type { AircraftD11Repository } from "@/ports/aircraft-d11-repository";

export function createAircraftD11(auth:AuthService, carriers:CarrierRepository, repo:AircraftD11Repository) {
  async function check(iata:string) {
    if (!await auth.currentUser()) throw new AuthenticationRequired();
    if (!await carriers.findAuthorised(iata)) throw new CarrierUnavailable();
  }
  async function editable(iata:string,typeCode:string,subtype:string,revision:string) {
    await check(iata);
    const current = await repo.get(iata,typeCode,subtype);
    if (!current.canEdit) throw new AircraftD11Denied();
    if (current.revision !== revision) throw new AircraftD11Conflict();
    return current;
  }
  return {
    async get(iata:string,typeCode:string,subtype:string) {
      await check(iata);
      return repo.get(iata,typeCode,subtype);
    },
    async save(iata:string,typeCode:string,subtype:string,revision:string,values:unknown) {
      const current = await editable(iata,typeCode,subtype,revision);
      if (!current.floorActive) throw new AircraftD11Invalid("Select Floor Loading Limits before entering its data.");
      return repo.save(iata,typeCode,subtype,revision,true,validateD11FloorLimits(values,current.floorLimits));
    },
    async setFloorActive(iata:string,typeCode:string,subtype:string,revision:string,applicable:boolean) {
      await editable(iata,typeCode,subtype,revision);
      return repo.save(iata,typeCode,subtype,revision,applicable,[]);
    },
  };
}
