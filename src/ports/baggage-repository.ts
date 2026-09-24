import type { BaggageOperationMode,BaggageRecord,BaggageSection,BaggageSnapshot,BaggageVariationMethod } from "@/domain/baggage-weights";
export interface BaggageRepository {
 get(iata:string):Promise<BaggageSnapshot>;
 save(iata:string,revision:string,section:BaggageSection,row:BaggageRecord,remove:boolean):Promise<void>;
 saveOperationMode(iata:string,revision:string,mode:BaggageOperationMode):Promise<void>;
 saveApplicability(iata:string,revision:string,defaultPerPiece:boolean):Promise<void>;
 saveVariationMethod(iata:string,revision:string,variation:string,method:BaggageVariationMethod):Promise<void>;
}
