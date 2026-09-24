import type{AircraftC4Snapshot,AircraftC4Values}from"@/domain/aircraft-c4";
export interface AircraftC4Repository{get(iata:string,typeCode:string,subtype:string):Promise<AircraftC4Snapshot>;save(iata:string,typeCode:string,subtype:string,revision:string,values:AircraftC4Values):Promise<AircraftC4Snapshot>}
