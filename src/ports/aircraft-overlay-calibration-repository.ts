export type AircraftOverlayKind="HOLD"|"SEAT";
export type AircraftOverlayCalibration={canEdit:boolean;offsetX:number|null;locked:boolean};

export interface AircraftOverlayCalibrationRepository{
  get(iata:string,typeCode:string,subtype:string,kind:AircraftOverlayKind):Promise<AircraftOverlayCalibration>;
  save(iata:string,typeCode:string,subtype:string,kind:AircraftOverlayKind,offsetX:number):Promise<AircraftOverlayCalibration>;
}
