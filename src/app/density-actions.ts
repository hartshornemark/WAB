"use server";
import {revalidatePath} from "next/cache";
import {densityServices} from "@/composition/services";
import {DensityConflict,DensityDenied,DensityInvalid} from "@/domain/density-settings";
import {AuthenticationRequired} from "@/domain/models";
export async function saveDensities(iata:string,revision:string,input:unknown){try{const snapshot=await(await densityServices()).save(iata,revision,input);revalidatePath(`/carrier/${encodeURIComponent(iata)}`);return {ok:true as const,snapshot};}catch(error){return {ok:false as const,error:error instanceof DensityInvalid?error.message:error instanceof DensityConflict?"Density settings changed. Copy your entries, then reload before saving.":error instanceof DensityDenied?"You no longer have permission to edit density settings.":error instanceof AuthenticationRequired?"Your session has ended. Please sign in again.":"Unable to save. Your entries are still here; please try again."};}}
