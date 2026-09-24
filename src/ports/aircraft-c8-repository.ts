import type{AircraftC8SectionKey,AircraftC8Snapshot}from"@/domain/aircraft-c8";
export interface AircraftC8Repository{get(iata:string,typeCode:string,subtype:string):Promise<AircraftC8Snapshot>;save(iata:string,typeCode:string,subtype:string,revision:string,section:AircraftC8SectionKey,values:unknown):Promise<AircraftC8Snapshot>}
