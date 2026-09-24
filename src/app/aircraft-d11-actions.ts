"use server";
import { revalidatePath } from "next/cache";
import { aircraftD11Services } from "@/composition/services";
import { AircraftD11Conflict, AircraftD11Denied, AircraftD11Invalid } from "@/domain/aircraft-d11";

const failure = (error:unknown) => ({ok:false as const,error:error instanceof AircraftD11Invalid?error.message:error instanceof AircraftD11Conflict?"D11 data changed. Reload before saving.":error instanceof AircraftD11Denied?"You do not have permission to edit D11.":"Unable to save D11."});
export async function saveAircraftD11(iata:string,typeCode:string,subtype:string,revision:string,values:unknown) {
  try {
    const snapshot=await(await aircraftD11Services()).save(iata,typeCode,subtype,revision,values);
    revalidatePath(`/carrier/${iata}/aircraft/${typeCode}/${subtype}/d11`);
    return {ok:true as const,snapshot};
  } catch(error) { return failure(error); }
}
export async function setAircraftD11FloorActive(iata:string,typeCode:string,subtype:string,revision:string,applicable:boolean) {
  try {
    const snapshot=await(await aircraftD11Services()).setFloorActive(iata,typeCode,subtype,revision,applicable);
    revalidatePath(`/carrier/${iata}/aircraft/${typeCode}/${subtype}/d11`);
    return {ok:true as const,snapshot};
  } catch(error) { return failure(error); }
}
