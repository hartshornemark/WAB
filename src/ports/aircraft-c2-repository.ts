import type{AircraftC2Snapshot,AircraftC2Values}from"@/domain/aircraft-c2";
export interface AircraftC2Repository{get(iata:string,typeCode:string,subtype:string):Promise<AircraftC2Snapshot>;save(iata:string,typeCode:string,subtype:string,revision:string,values:AircraftC2Values):Promise<AircraftC2Snapshot>}
