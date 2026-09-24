import type{AircraftC5Section,AircraftC5Snapshot,AircraftC5Values}from"@/domain/aircraft-c5";
export interface AircraftC5Repository{get(iata:string,typeCode:string,subtype:string):Promise<AircraftC5Snapshot>;save(iata:string,typeCode:string,subtype:string,revision:string,section:AircraftC5Section,values:AircraftC5Values):Promise<AircraftC5Snapshot>}
