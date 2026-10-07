"use server";
import{createHash}from"node:crypto";
import{revalidatePath}from"next/cache";
import{flightScheduleServices}from"@/composition/services";
import{FlightScheduleConflict,FlightScheduleDenied,FlightScheduleInvalid}from"@/domain/flight-schedules";
import{SsimChapter7Invalid}from"@/domain/ssim-chapter7";
import type{ScheduleActionState}from"@/domain/flight-schedule-action-state";

const message=(error:unknown)=>error instanceof FlightScheduleInvalid||error instanceof FlightScheduleConflict||error instanceof FlightScheduleDenied||error instanceof SsimChapter7Invalid?error.message:"The schedule operation was not completed. Please try again.";

export async function importSsimSchedule(iata:string,_previous:ScheduleActionState,formData:FormData):Promise<ScheduleActionState>{
  try{
    const file=formData.get("scheduleFile");
    if(!(file instanceof File)||file.size===0)return{ok:false,message:"Select an SSIM Chapter 7 TXT file."};
    if(file.size>2*1024*1024)return{ok:false,message:"The SSIM file is larger than the 2 MB upload limit."};
    const bytes=new Uint8Array(await file.arrayBuffer()),text=new TextDecoder("utf-8",{fatal:true}).decode(bytes),sha256=createHash("sha256").update(bytes).digest("hex");
    const result=await(await flightScheduleServices()).importFile(iata,{fileName:file.name,text,sha256,sizeBytes:file.size});
    revalidatePath(`/carrier/${iata}/flight-schedules`);
    return{ok:true,message:`Validated ${result.normalizedLegs.toLocaleString()} flight legs. Review this edition, then publish it when ready.`,importId:result.importId,status:result.status,legs:result.normalizedLegs};
  }catch(error){console.error("[SSIM import]",error);return{ok:false,message:message(error)}}
}

export async function publishSsimSchedule(iata:string,importId:string):Promise<ScheduleActionState>{
  try{const result=await(await flightScheduleServices()).publish(iata,importId);revalidatePath(`/carrier/${iata}/flight-schedules`);return{ok:true,message:"The schedule is now published for daily load-control planning.",importId:result.importId,status:result.status,legs:result.normalizedLegs}}
  catch(error){console.error("[SSIM publish]",error);return{ok:false,message:message(error)}}
}

export async function cancelScheduleEdition(iata:string,importId:string):Promise<ScheduleActionState>{
  try{await(await flightScheduleServices()).cancel(iata,importId);revalidatePath(`/carrier/${iata}/flight-schedules`);return{ok:true,message:"Schedule cancelled. Its flights have been removed from Load Control; other published schedules remain active."}}
  catch(error){console.error("[Schedule cancellation]",error);return{ok:false,message:message(error)}}
}

export async function createScheduleRevision(iata:string,importId:string):Promise<ScheduleActionState>{
  try{const revisionId=await(await flightScheduleServices()).createRevision(iata,importId);revalidatePath(`/carrier/${iata}/flight-schedules`);return{ok:true,message:"Editable schedule revision created.",importId:revisionId,status:"VALIDATED"}}
  catch(error){console.error("[Schedule revision]",error);return{ok:false,message:message(error)}}
}

export async function saveScheduleParameters(iata:string,scheduleLegId:string,values:unknown):Promise<ScheduleActionState>{
  try{await(await flightScheduleServices()).saveParameters(iata,scheduleLegId,values);revalidatePath(`/carrier/${iata}/flight-schedules`);return{ok:true,message:"Load Control parameters saved."}}
  catch(error){console.error("[Schedule parameters]",error);return{ok:false,message:message(error)}}
}

export async function saveScheduleSegmentDefault(iata:string,departureAirport:string,arrivalAirport:string,aircraftType:string,values:unknown):Promise<ScheduleActionState>{
  try{await(await flightScheduleServices()).saveSegmentDefault(iata,departureAirport,arrivalAirport,aircraftType,values);revalidatePath(`/carrier/${iata}/flight-schedules`);return{ok:true,message:`Defaults saved for ${departureAirport}–${arrivalAirport}. Matching schedule legs have been updated.`}}
  catch(error){console.error("[Schedule segment defaults]",error);return{ok:false,message:message(error)}}
}

export async function deleteScheduleSegmentDefault(iata:string,departureAirport:string,arrivalAirport:string,aircraftType:string):Promise<ScheduleActionState>{
  try{await(await flightScheduleServices()).deleteSegmentDefault(iata,departureAirport,arrivalAirport,aircraftType);revalidatePath(`/carrier/${iata}/flight-schedules`);return{ok:true,message:`Defaults removed for ${departureAirport}–${arrivalAirport}.`}}
  catch(error){console.error("[Schedule segment default deletion]",error);return{ok:false,message:message(error)}}
}

export async function createManualSchedule(iata:string,name:string,seasonCode:string):Promise<ScheduleActionState>{
  try{const importId=await(await flightScheduleServices()).createManual(iata,name,seasonCode);revalidatePath(`/carrier/${iata}/flight-schedules`);return{ok:true,message:"Manual schedule created. Add its first flight leg.",importId,status:"DRAFT"}}
  catch(error){console.error("[Manual schedule create]",error);return{ok:false,message:message(error)}}
}

export async function saveManualScheduleLeg(iata:string,importId:string,values:unknown,scheduleLegId:string|null=null):Promise<ScheduleActionState>{
  try{const result=await(await flightScheduleServices()).saveManualLeg(iata,importId,scheduleLegId,values);revalidatePath(`/carrier/${iata}/flight-schedules`);return{ok:true,message:scheduleLegId?"Manual flight leg updated.":"Manual flight leg saved. You can add another leg or publish the edition.",importId:result.importId,status:result.status}}
  catch(error){console.error("[Manual schedule leg]",error);return{ok:false,message:message(error)}}
}

export async function saveManualScheduleItinerary(iata:string,importId:string,values:unknown):Promise<ScheduleActionState>{
  try{const result=await(await flightScheduleServices()).saveManualItinerary(iata,importId,values);revalidatePath(`/carrier/${iata}/flight-schedules`);return{ok:true,message:`Manual itinerary saved with ${result.scheduleLegIds.length} segment${result.scheduleLegIds.length===1?"":"s"}. You can add another flight or publish the edition.`,importId:result.importId,status:result.status,legs:result.scheduleLegIds.length}}
  catch(error){console.error("[Manual schedule itinerary]",error);return{ok:false,message:message(error)}}
}

export async function deleteManualScheduleLeg(iata:string,importId:string,scheduleLegId:string):Promise<ScheduleActionState>{
  try{await(await flightScheduleServices()).deleteManualLeg(iata,importId,scheduleLegId);revalidatePath(`/carrier/${iata}/flight-schedules`);return{ok:true,message:"Manual flight leg deleted.",importId}}
  catch(error){console.error("[Manual schedule leg deletion]",error);return{ok:false,message:message(error)}}
}

export async function deleteScheduleEdition(iata:string,importId:string):Promise<ScheduleActionState>{
  try{await(await flightScheduleServices()).deleteEdition(iata,importId);revalidatePath(`/carrier/${iata}/flight-schedules`);return{ok:true,message:"Schedule edition deleted."}}
  catch(error){console.error("[Schedule edition deletion]",error);return{ok:false,message:message(error)}}
}
