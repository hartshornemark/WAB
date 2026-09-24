import { AuthenticationRequired,CarrierUnavailable } from "@/domain/models";
import { BaggageDenied,BaggageInvalid,BaggageConflict,validateBaggage,type BaggageOperationMode,type BaggageSection } from "@/domain/baggage-weights";
import type { AuthService } from "@/ports/auth-service";
import type { CarrierRepository } from "@/ports/carrier-repository";
import type { BaggageRepository } from "@/ports/baggage-repository";
export function createBaggageWeights(auth:AuthService,carriers:CarrierRepository,repository:BaggageRepository){
 async function check(iata:string){if(!await auth.currentUser())throw new AuthenticationRequired();if(!iata||iata.length>32||!await carriers.findAuthorised(iata))throw new CarrierUnavailable();}
 return {
  async get(iata:string){await check(iata);return repository.get(iata);},
  async save(iata:string,revision:string,section:BaggageSection,input:unknown,remove=false){
   await check(iata);const current=await repository.get(iata);
   if(!current.canEdit)throw new BaggageDenied();
   if(current.revision!==revision)throw new BaggageConflict();
   if(!["defaults","weights","planning"].includes(section))throw new BaggageInvalid("Unknown section.");
   if(!current.unit)throw new BaggageInvalid("Save a Weight Unit on B1 first.");
   let row;
   if(remove){
    const id=(input as {id?:unknown})?.id;
    row=(section==="weights"?current.weights:current.planning).find(r=>r.id===id);
    if(section==="defaults"||!row||row.baseline)throw new BaggageInvalid("The default record cannot be removed.");
   }else row=validateBaggage(section,input,current);
   await repository.save(iata,revision,section,row,remove);
  },
  async saveApplicability(iata:string,revision:string,defaultPerPiece:boolean){
   await check(iata);const current=await repository.get(iata);
   if(!current.canEdit)throw new BaggageDenied();if(current.revision!==revision)throw new BaggageConflict();
   if(typeof defaultPerPiece!=="boolean")throw new BaggageInvalid("Choose a Baggage Weight method.");
   await repository.saveApplicability(iata,revision,defaultPerPiece);
  },
  async saveOperationMode(iata:string,revision:string,mode:BaggageOperationMode){
   await check(iata);const current=await repository.get(iata);
   if(!current.canEdit)throw new BaggageDenied();if(current.revision!==revision)throw new BaggageConflict();
   if(!["STANDARD","ACTUAL"].includes(mode))throw new BaggageInvalid("Choose Standard or Actual Baggage Weight Operations.");
   await repository.saveOperationMode(iata,revision,mode);
  },
  async saveVariationStandard(iata:string,revision:string,variation:unknown){
   await check(iata);const current=await repository.get(iata);
   if(!current.canEdit)throw new BaggageDenied();if(current.revision!==revision)throw new BaggageConflict();
   if(typeof variation!=="string"||!current.variations.some(item=>item.code===variation))throw new BaggageInvalid("Choose a Flight Variation saved on B3.");
   if(current.weights.some(row=>row.values.variation===variation))throw new BaggageInvalid("Remove the saved variation-specific Baggage Weight records before selecting Standard Baggage Weights.");
   await repository.saveVariationStandard(iata,revision,variation);
  }
 };
}
