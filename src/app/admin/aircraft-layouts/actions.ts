"use server";
import {revalidatePath} from "next/cache";
import {aircraftLayoutServices} from "@/composition/services";
export async function publishVerifiedAircraftLayouts(){
 try {const result=await(await aircraftLayoutServices()).publishVerified();if(result.ok)revalidatePath("/admin/aircraft-layouts");return result;}
 catch{return {ok:false,message:"Administrator access is required."};}
}
export async function publishAircraftLayoutVersion(typeCode:string,subtype:string,version:number){
 try {const result=await(await aircraftLayoutServices()).publishVersion(typeCode,subtype,version);if(result.ok)revalidatePath("/admin/aircraft-layouts");return result;}
 catch{return {ok:false,message:"Administrator access is required."};}
}
