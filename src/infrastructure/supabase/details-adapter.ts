import "server-only";
import { DataUnavailable } from "@/domain/models";
import { DetailsConflict, DetailsDenied, emptyDetails, type DetailsSnapshot } from "@/domain/carrier-details";
import type { CarrierDetailsRepository } from "@/ports/carrier-details-repository";
import type { RequestClient } from "./server";
function snapshot(data: unknown): DetailsSnapshot {
  if (!data || typeof data !== "object") throw new DataUnavailable();
  const row = data as DetailsSnapshot;
  if (typeof row.canView !== "boolean" || typeof row.canEdit !== "boolean" || typeof row.exists !== "boolean" || typeof row.revision !== "string" || !row.values) throw new DataUnavailable();
  const values = { ...emptyDetails };
  for (const key of Object.keys(values) as (keyof typeof values)[]) {
    if (typeof row.values[key] !== "string") throw new DataUnavailable();
    values[key] = row.values[key];
  }
  return { canView: row.canView, canEdit: row.canEdit, exists: row.exists, revision: row.revision, values };
}
export function createDetailsAdapter(client: RequestClient): CarrierDetailsRepository {
  const api = () => client.schema("Basic_Carrier_Record");
  return {
    async get(iata) {
      const { data, error } = await api().rpc("get_carrier_details", { p_iata: iata });
      if (error) throw new DataUnavailable("Unable to load carrier details.");
      return snapshot(data);
    },
    async save(iata, revision, values, section) {
      const { data, error } = await api().rpc(section === "contact" ? "save_carrier_contacts" : "save_carrier_details", { p_iata: iata, p_revision: revision, p_values: values });
      if (error?.code === "42501") throw new DetailsDenied();
      if (error?.code === "40001") throw new DetailsConflict();
      if (error) throw new DataUnavailable("Unable to save carrier details.");
      return snapshot(data);
    },
  };
}
