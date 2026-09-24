import type { CrewValues, CrewSnapshot } from "@/domain/crew-weights";
export interface CrewRepository {
  get(iata: string): Promise<CrewSnapshot>;
  save(iata: string, revision: string, values: CrewValues): Promise<CrewSnapshot>;
}
