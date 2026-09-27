import type {AircraftLayoutRepository} from "@/ports/aircraft-layout-repository";
import type {AuthService} from "@/ports/auth-service";
import {AuthenticationRequired} from "@/domain/models";
export function createAircraftLayouts(auth:AuthService,repo:AircraftLayoutRepository){
 async function requireUser(){if(!await auth.currentUser())throw new AuthenticationRequired();}
 return {
  async load(iata:string,typeCode:string,subtype:string){await requireUser();return repo.load(iata,typeCode,subtype);},
  async list(){await requireUser();return repo.list();},
  async publishVerified(){await requireUser();return repo.publishVerified();},
  async publishVersion(typeCode:string,subtype:string,version:number){await requireUser();return repo.publishVersion(typeCode,subtype,version);},
 };
}
