import type{MasterAirport,MasterAirportConfiguration,MasterAirportInput}from"@/domain/master-airports";
export interface MasterAirportRepository{get():Promise<MasterAirportConfiguration>;save(originalIata:string|null,value:MasterAirportInput):Promise<MasterAirport>}
