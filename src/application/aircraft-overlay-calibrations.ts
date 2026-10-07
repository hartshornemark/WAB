import{AuthenticationRequired,CarrierUnavailable}from"@/domain/models";
import type{AircraftOverlayCalibrationRepository,AircraftOverlayKind}from"@/ports/aircraft-overlay-calibration-repository";
import type{AuthService}from"@/ports/auth-service";
import type{CarrierRepository}from"@/ports/carrier-repository";

export function createAircraftOverlayCalibrations(auth:AuthService,carriers:CarrierRepository,repository:AircraftOverlayCalibrationRepository){
  async function access(iata:string){if(!await auth.currentUser())throw new AuthenticationRequired();if(!await carriers.findAuthorised(iata))throw new CarrierUnavailable()}
  return{
    async get(iata:string,typeCode:string,subtype:string,kind:AircraftOverlayKind){await access(iata);return repository.get(iata,typeCode,subtype,kind)},
    async save(iata:string,typeCode:string,subtype:string,kind:AircraftOverlayKind,offsetX:number){await access(iata);if(!Number.isFinite(offsetX)||Math.abs(offsetX)>5000)throw new Error("Choose a valid overlay position.");return repository.save(iata,typeCode,subtype,kind,offsetX)},
  };
}
