import type {AircraftLayoutCalibration} from "@/domain/hold-layout";
import type {LayoutVersion} from "@/domain/aircraft-layout-template";
export interface AircraftLayoutRepository {
 load(iata:string,typeCode:string,subtype:string):Promise<AircraftLayoutCalibration>;
 list():Promise<LayoutVersion[]>;
 publishVerified():Promise<{ok:boolean;message:string}>;
 publishVersion(typeCode:string,subtype:string,version:number):Promise<{ok:boolean;message:string}>;
}
