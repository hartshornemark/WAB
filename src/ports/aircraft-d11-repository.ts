import type { AircraftD11Snapshot } from "@/domain/aircraft-d11";
export interface AircraftD11Repository {
  get(iata:string,typeCode:string,subtype:string):Promise<AircraftD11Snapshot>;
  save(iata:string,typeCode:string,subtype:string,revision:string,applicable:boolean,rows:unknown[]):Promise<AircraftD11Snapshot>;
}
