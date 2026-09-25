import type { DetailValues, DetailsSnapshot, DetailsSaveSection } from "@/domain/carrier-details";
export interface CarrierDetailsRepository {
  get(iata: string): Promise<DetailsSnapshot>;
  save(iata: string, revision: string, values: DetailValues, section?: DetailsSaveSection): Promise<DetailsSnapshot>;
}
