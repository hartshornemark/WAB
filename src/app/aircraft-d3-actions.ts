"use server";
import { revalidatePath } from "next/cache";
import { aircraftD3Services } from "@/composition/services";
import { AircraftD3Conflict, AircraftD3Denied, AircraftD3Invalid } from "@/domain/aircraft-d3";
const message=(e:unknown)=>e instanceof AircraftD3Invalid?e.message:e instanceof AircraftD3Conflict?"D3 data changed. Reload before saving.":e instanceof AircraftD3Denied?"You do not have permission to edit D3.":"The D3 save was not completed. Please try again; if the problem continues, reload the page.";
const report=(operation:string,e:unknown)=>console.error(`[D3 ${operation}]`,e);
export async function saveAircraftD3(i:string,t:string,s:string,r:string,o:string|null,v:unknown){try{const snapshot=await(await aircraftD3Services()).save(i,t,s,r,o,v);revalidatePath(`/carrier/${i}/aircraft/${t}/${s}/d3`);return{ok:true as const,snapshot}}catch(e){report("save",e);return{ok:false as const,error:message(e)}}}
export async function importAircraftD3(i:string,t:string,s:string,r:string,sourceTypeCode:string,sourceSubtype:string,v:unknown){try{const snapshot=await(await aircraftD3Services()).importAll(i,t,s,r,sourceTypeCode,sourceSubtype,v);revalidatePath(`/carrier/${i}/aircraft/${t}/${s}/d3`);return{ok:true as const,snapshot}}catch(e){report("import",e);return{ok:false as const,error:message(e)}}}
export async function deleteAircraftD3(i:string,t:string,s:string,r:string,h:string,c:string){try{const snapshot=await(await aircraftD3Services()).remove(i,t,s,r,h,c);revalidatePath(`/carrier/${i}/aircraft/${t}/${s}/d3`);return{ok:true as const,snapshot}}catch(e){return{ok:false as const,error:message(e)}}}
