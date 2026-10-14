import type{OperationalTimelineConfiguration,OperationalTimelineSnapshot,OperationalTimelineValues}from"@/domain/operational-timeline";
export interface OperationalTimelineRepository{
  get(iata:string):Promise<OperationalTimelineSnapshot>;
  resolve(iata:string,aircraftType:string):Promise<OperationalTimelineConfiguration>;
  save(iata:string,aircraftType:string|null,expectedRevision:number,values:OperationalTimelineValues):Promise<OperationalTimelineSnapshot>;
  remove(iata:string,aircraftType:string,expectedRevision:number):Promise<OperationalTimelineSnapshot>;
}
