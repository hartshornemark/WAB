import type { CrewValues, CrewSnapshot } from "@/domain/crew-weights";
export interface CrewRepository {
  saveHold(iata:string,revision:string,code:string|null,values:unknown):Promise<CrewSnapshot>;
  get(iata: string): Promise<CrewSnapshot>;
  save(iata: string, revision: string, values: CrewValues): Promise<CrewSnapshot>;
}
