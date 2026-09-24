import type {DensitySnapshot,DensityValues} from "@/domain/density-settings";
export interface DensityRepository {get(iata:string):Promise<DensitySnapshot>;save(iata:string,revision:string,values:DensityValues):Promise<DensitySnapshot>}
