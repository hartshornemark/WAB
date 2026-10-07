"use server";
import{revalidatePath}from"next/cache";
import{masterAirportServices}from"@/composition/services";
import{AuthenticationRequired,DataUnavailable}from"@/domain/models";
import{MasterAirportDenied,MasterAirportExists,MasterAirportInvalid,type MasterAirportField,type MasterAirportInput}from"@/domain/master-airports";
export type AirportActionState={ok:boolean;message:string;field?:MasterAirportField};
export async function saveMasterAirportAction(originalIata:string|null,value:MasterAirportInput):Promise<AirportActionState>{
 try{await(await masterAirportServices()).save(originalIata,value);revalidatePath("/admin/airports");revalidatePath("/carriers");return{ok:true,message:`Airport ${value.iata.trim().toUpperCase()} saved.`}}
 catch(error){if(error instanceof MasterAirportInvalid)return{ok:false,message:error.message,field:error.field};if(error instanceof MasterAirportExists)return{ok:false,message:`That ${error.field.toUpperCase()} airport code already exists.`,field:error.field};if(error instanceof AuthenticationRequired)return{ok:false,message:"Your session has ended. Sign in again."};if(error instanceof MasterAirportDenied)return{ok:false,message:"Only a Solution Administrator can maintain master airports."};return{ok:false,message:error instanceof DataUnavailable?"Airport configuration is temporarily unavailable.":"The airport could not be saved."}}
}
