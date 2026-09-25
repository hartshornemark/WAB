import "server-only";
import {DataUnavailable} from "@/domain/models";
import {DensityConflict,DensityDenied,DensityInvalid,type DensitySnapshot} from "@/domain/density-settings";
import type {DensityRepository} from "@/ports/density-repository";
import type {RequestClient} from "./server";
function snapshot(data:unknown):DensitySnapshot{const s=data as DensitySnapshot;if(!s||typeof s.canView!=="boolean"||typeof s.canEdit!=="boolean"||typeof s.exists!=="boolean"||typeof s.revision!=="string"||!["","KG","LB"].includes(s.weightUnit)||!["","m3","ft3"].includes(s.volumeUnit)||![s.values?.baggage,s.values?.cargo,s.values?.mail].every(v=>typeof v==="string"))throw new DataUnavailable();if(s.defaults&&!Object.values(s.defaults).every(v=>typeof v==="string"))throw new DataUnavailable();return s;}
function fail(error:{code?:string}|null){if(!error)return;if(error.code==="42501")throw new DensityDenied();if(["23505","40001","40P01"].includes(error.code??""))throw new DensityConflict();if(["23514","23503","22003","22P02","22023"].includes(error.code??""))throw new DensityInvalid("Check the density values and carrier units.");throw new DataUnavailable();}
export function createDensityAdapter(client:RequestClient):DensityRepository{
 return {async get(iata){const r=await client.schema("Basic_Carrier_Record").rpc("get_carrier_densities",{p_iata:iata});fail(r.error);return snapshot(r.data);},async save(iata,revision,values){const r=await client.schema("Basic_Carrier_Record").rpc("save_carrier_densities",{p_iata:iata,p_revision:revision,p_values:values});fail(r.error);return snapshot(r.data);}};
}
