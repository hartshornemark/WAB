import "server-only";
import { DataUnavailable } from "@/domain/models";
import { PassengerConflict, PassengerDenied, PassengerInvalid, passengerFields, type PassengerSnapshot } from "@/domain/passenger-weights";
import type { PassengerRepository } from "@/ports/passenger-repository";
import type { RequestClient } from "./server";
function snapshot(data: unknown): PassengerSnapshot {
  if (!data || typeof data !== "object") throw new DataUnavailable();
  const s = data as PassengerSnapshot;
  if (typeof s.canView !== "boolean" || typeof s.canEdit !== "boolean" || typeof s.revision !== "string" || ![null,"KG","LB"].includes(s.unit) || typeof s.variationsReviewed !== "boolean" || typeof s.classWeightsReviewed !== "boolean" || !Array.isArray(s.rows) || !Array.isArray(s.classes) || !Array.isArray(s.variations) || !Array.isArray(s.masterVariations)) throw new DataUnavailable();
  for (const list of [s.classes,s.variations,s.masterVariations]) for (const v of list) {
    if (!v || typeof v.code !== "string" || typeof v.description !== "string") throw new DataUnavailable();
  }
  for (const v of [...(s.defaultWeights ? [s.defaultWeights] : []),...s.rows]) {
    if (!v || typeof v.includesHandBaggage !== "boolean" || typeof v.remarks !== "string") throw new DataUnavailable();
    for (const key of passengerFields) if (v[key] !== null && (typeof v[key] !== "number" || !Number.isInteger(v[key]) || v[key]! < 0)) throw new DataUnavailable();
  }
  for (const row of s.rows) if (typeof row.id !== "string" || (row.classCode !== null && typeof row.classCode !== "string") || (row.variation !== null && typeof row.variation !== "string")) throw new DataUnavailable();
  return s;
}
export function createPassengerAdapter(client: RequestClient): PassengerRepository {
  return {
    async get(iata) {
      const { data,error } = await client.schema("Basic_Carrier_Record").rpc("get_carrier_passenger_weights",{p_iata:iata});
      if (error) throw new DataUnavailable("Passenger weights are unavailable.");
      return snapshot(data);
    },
    async save(iata,revision,section,values) {
      const { data,error } = await client.schema("Basic_Carrier_Record").rpc("save_carrier_passenger_weights",{p_iata:iata,p_revision:revision,p_section:section,p_values:values});
      if (error?.code === "42501") throw new PassengerDenied();
      if (error?.code === "40001" || error?.code === "40P01") throw new PassengerConflict();
      if (error?.code === "23503") throw new PassengerInvalid("A class or variation is missing or still used by a weight set. Save its definition first, or remove the linked weight sets before removing it.");
      if (error?.code === "23505") throw new PassengerInvalid("Duplicate class/variation weight sets or variation labels are not allowed.");
      if (error && ["22023","22P02","23514","23502"].includes(error.code)) throw new PassengerInvalid("Check the codes, descriptions and weights. Separate hand-baggage weight is required when excluded.");
      if (error) throw new DataUnavailable();
      return snapshot(data);
    },
  };
}
