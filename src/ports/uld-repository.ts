import type {UldSnapshot,UldRow} from "@/domain/uld-specifications";
export interface UldRepository {get(iata:string,typeCode:string,subtype:string):Promise<UldSnapshot>;save(iata:string,typeCode:string,subtype:string,revision:string,rows:UldRow[]):Promise<UldSnapshot>;saveApplicability(iata:string,typeCode:string,subtype:string,revision:string,utilisesUlds:boolean):Promise<UldSnapshot>}
