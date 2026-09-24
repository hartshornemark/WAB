import type{AircraftC7Section,AircraftC7SectionKey,AircraftC7Snapshot}from"@/domain/aircraft-c7";
export interface AircraftC7Repository{get(iata:string,typeCode:string,subtype:string):Promise<AircraftC7Snapshot>;save(iata:string,typeCode:string,subtype:string,revision:string,section:AircraftC7SectionKey,values:AircraftC7Section):Promise<AircraftC7Snapshot>}
