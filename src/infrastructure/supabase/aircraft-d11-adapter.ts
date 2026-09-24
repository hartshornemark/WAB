import "server-only";
import { DataUnavailable } from "@/domain/models";
import { AircraftD11Conflict, AircraftD11Denied, AircraftD11Invalid, type AircraftD11Snapshot } from "@/domain/aircraft-d11";
import type { AircraftD11Repository } from "@/ports/aircraft-d11-repository";
import type { RequestClient } from "./server";
import type { Json } from "./database.types";

const fail = (error:{code?:string}|null) => {
  if (!error) return;
  if (error.code === "42501") throw new AircraftD11Denied();
  if (error.code === "40001") throw new AircraftD11Conflict();
  if (["23514","23503","23505","22023","23502","22P02","22001"].includes(error.code??"")) throw new AircraftD11Invalid("Check every D11 Floor Loading Limit.");
  throw new DataUnavailable();
};
const snapshot = (data:unknown) => {
  const value = data as AircraftD11Snapshot;
  if (!value || typeof value.canEdit !== "boolean" || typeof value.combinedActive !== "boolean" || typeof value.floorActive !== "boolean" || typeof value.asymmetricalActive !== "boolean" || !Array.isArray(value.floorLimits)) throw new DataUnavailable();
  return value;
};
export function createAircraftD11Adapter(client:RequestClient):AircraftD11Repository {
  return {
    async get(iata,typeCode,subtype) {
      const result = await client.schema("Basic_Carrier_Record").rpc("get_aircraft_d11",{p_iata:iata,p_type_code:typeCode,p_subtype:subtype});
      fail(result.error);
      return snapshot(result.data);
    },
    async save(iata,typeCode,subtype,revision,applicable,rows) {
      const result = await client.schema("Basic_Carrier_Record").rpc("save_aircraft_d11",{p_iata:iata,p_type_code:typeCode,p_subtype:subtype,p_revision:revision,p_applicable:applicable,p_rows:rows as Json});
      fail(result.error);
      return snapshot(result.data);
    },
  };
}
