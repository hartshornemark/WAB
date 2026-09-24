import type { CommodityCode, CommoditySnapshot } from "@/domain/commodity-codes";
export interface CommodityRepository {
  get(iata: string): Promise<CommoditySnapshot>;
  save(iata: string, revision: string, rows: CommodityCode[]): Promise<CommoditySnapshot>;
}
