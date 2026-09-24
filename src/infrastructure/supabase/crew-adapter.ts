import "server-only";
import { DataUnavailable } from "@/domain/models";
import { CrewConflict, CrewDenied, CrewInvalid, crewWeightFields, holdCategories, type CrewSnapshot, type CrewValues } from "@/domain/crew-weights";
import type { CrewRepository } from "@/ports/crew-repository";
import type { RequestClient } from "./server";
function snapshot(data: unknown): CrewSnapshot {
  if (!data || typeof data !== "object") throw new DataUnavailable();
  const row = data as CrewSnapshot;
  if (typeof row.canView !== "boolean" || typeof row.canEdit !== "boolean" || typeof row.exists !== "boolean" || typeof row.revision !== "string" || ![null,"KG","LB"].includes(row.unit) || !row.values || typeof row.values.includesHandBaggage !== "boolean") throw new DataUnavailable();
  for (const { key } of holdCategories) {
    if (typeof row.values[key] !== "boolean") throw new DataUnavailable("Crew Hold Baggage selection is awaiting the database update.");
  }
  const values = { includesHandBaggage: row.values.includesHandBaggage, allFlights: row.values.allFlights, longhaul: row.values.longhaul, shorthaul: row.values.shorthaul } as CrewValues;
  for (const key of crewWeightFields) {
    const value = row.values[key];
    if (value !== null && (typeof value !== "number" || !Number.isInteger(value) || value < 0 || value > 2147483647)) throw new DataUnavailable();
    values[key] = value;
  }
  return { canView: row.canView, canEdit: row.canEdit, exists: row.exists, revision: row.revision, unit: row.unit, values };
}
export function createCrewAdapter(client: RequestClient): CrewRepository {
  return {
    async get(iata) {
      const { data, error } = await client.schema("Basic_Carrier_Record").rpc("get_carrier_crew_weights", { p_iata: iata });
      if (error) throw new DataUnavailable("Unable to load crew weights.");
      return snapshot(data);
    },
    async save(iata, revision, values) {
      const { data, error } = await client.schema("Basic_Carrier_Record").rpc("save_carrier_crew_weights", { p_iata: iata, p_revision: revision, p_values: values });
      if (error?.code === "42501") throw new CrewDenied();
      if (error?.code === "40001") throw new CrewConflict();
      if (error?.code === "22023" || error?.code === "23514") throw new CrewInvalid("Check the weights. Both hand-baggage weights are required when they are not included in crew weights.");
      if (error?.code === "23503") throw new CrewInvalid("Complete and save Carrier Details and the B1 weight unit first.");
      if (error) throw new DataUnavailable();
      return snapshot(data);
    },
  };
}
