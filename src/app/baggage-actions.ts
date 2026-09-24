"use server";
import { revalidatePath } from "next/cache";
import { baggageServices } from "@/composition/services";
import { AuthenticationRequired } from "@/domain/models";
import { BaggageConflict,BaggageDenied,BaggageInvalid,type BaggageOperationMode,type BaggageSection } from "@/domain/baggage-weights";
export async function saveBaggage(iata:string,revision:string,section:BaggageSection,input:unknown,remove=false){
 try{const service=await baggageServices();await service.save(iata,revision,section,input,remove);const snapshot=await service.get(iata);revalidatePath(`/carrier/${encodeURIComponent(iata)}/baggage-weights`);return {ok:true as const,snapshot};}
 catch(error){return {ok:false as const,error:error instanceof BaggageInvalid?error.message:error instanceof BaggageConflict?"These settings changed. Copy your entries, then reload before saving.":error instanceof BaggageDenied?"You no longer have permission to edit these settings.":error instanceof AuthenticationRequired?"Your session has ended. Please sign in again.":"Unable to save. Your entries are still here; please try again."};}
}
export async function saveBaggageApplicability(iata:string,revision:string,defaultPerPiece:boolean){
 try{const service=await baggageServices();await service.saveApplicability(iata,revision,defaultPerPiece);const snapshot=await service.get(iata);revalidatePath(`/carrier/${encodeURIComponent(iata)}/baggage-weights`);return{ok:true as const,snapshot};}
 catch(error){return{ok:false as const,error:error instanceof BaggageInvalid?error.message:error instanceof BaggageConflict?"These settings changed. Reload before changing the selection.":error instanceof BaggageDenied?"You no longer have permission to edit these settings.":error instanceof AuthenticationRequired?"Your session has ended. Please sign in again.":"Unable to save the selection. Please try again."};}
}
export async function saveBaggageOperationMode(iata:string,revision:string,mode:BaggageOperationMode){
 try{const service=await baggageServices();await service.saveOperationMode(iata,revision,mode);const snapshot=await service.get(iata);revalidatePath(`/carrier/${encodeURIComponent(iata)}/baggage-weights`);return{ok:true as const,snapshot};}
 catch(error){return{ok:false as const,error:error instanceof BaggageInvalid?error.message:error instanceof BaggageConflict?"These settings changed. Reload before changing the operation method.":error instanceof BaggageDenied?"You no longer have permission to edit these settings.":error instanceof AuthenticationRequired?"Your session has ended. Please sign in again.":"Unable to save the operation method. Please try again."};}
}
export async function saveBaggageVariationStandard(iata:string,revision:string,variation:string){
 try{const service=await baggageServices();await service.saveVariationStandard(iata,revision,variation);const snapshot=await service.get(iata);revalidatePath(`/carrier/${encodeURIComponent(iata)}/baggage-weights`);return{ok:true as const,snapshot};}
 catch(error){return{ok:false as const,error:error instanceof BaggageInvalid?error.message:error instanceof BaggageConflict?"These settings changed. Reload before recording the variation decision.":error instanceof BaggageDenied?"You no longer have permission to edit these settings.":error instanceof AuthenticationRequired?"Your session has ended. Please sign in again.":"Unable to save the variation decision. Please try again."};}
}
