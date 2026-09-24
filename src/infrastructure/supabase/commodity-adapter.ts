import "server-only";
import { DataUnavailable } from "@/domain/models";
import { CommodityConflict, CommodityDenied, CommodityInvalid, type CommodityCode, type CommoditySnapshot } from "@/domain/commodity-codes";
import type { CommodityRepository } from "@/ports/commodity-repository";
import type { RequestClient } from "./server";
function rows(value: unknown): CommodityCode[] {
  if (!Array.isArray(value)) throw new DataUnavailable();
  return value.map(row => {
    if (!row || typeof row.code !== "string" || typeof row.description !== "string") throw new DataUnavailable();
    return { code: row.code, description: row.description };
  });
}
function snapshot(value: unknown): CommoditySnapshot {
  if (!value || typeof value !== "object") throw new DataUnavailable();
  const v = value as CommoditySnapshot;
  if (typeof v.canView !== "boolean" || typeof v.canEdit !== "boolean" || typeof v.revision !== "string") throw new DataUnavailable();
  return { canView: v.canView, canEdit: v.canEdit, revision: v.revision, rows: rows(v.rows), defaults: rows(v.defaults) };
}
export function createCommodityAdapter(client: RequestClient): CommodityRepository {
  return {
    async get(iata) {
      const { data, error } = await client.schema("Basic_Carrier_Record").rpc("get_carrier_commodity_codes", { p_iata: iata });
      if (error) throw new DataUnavailable("Unable to load commodity codes.");
      return snapshot(data);
    },
    async save(iata, revision, values) {
      const { data, error } = await client.schema("Basic_Carrier_Record").rpc("save_carrier_commodity_codes", { p_iata: iata, p_revision: revision, p_rows: values });
      if (error?.code === "42501") throw new CommodityDenied();
      if (error?.code === "40001") throw new CommodityConflict();
      if (error?.code === "22023") throw new CommodityInvalid("Check the codes and descriptions, then try again.");
      if (error) throw new DataUnavailable();
      return snapshot(data);
    },
  };
}
