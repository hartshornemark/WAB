import type { DetailValues, DetailsSnapshot } from "@/domain/carrier-details";
export interface CarrierDetailsRepository {
  get(iata: string): Promise<DetailsSnapshot>;
  save(iata: string, revision: string, values: DetailValues): Promise<DetailsSnapshot>;
}
