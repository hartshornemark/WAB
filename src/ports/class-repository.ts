import type { CarrierClass, ClassSnapshot } from "@/domain/class-codes";
export interface ClassRepository {
  get(iata: string): Promise<ClassSnapshot>;
  save(iata: string, revision: string, rows: CarrierClass[]): Promise<ClassSnapshot>;
}
