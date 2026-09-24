import "server-only";
import type { CarrierRepository } from "@/ports/carrier-repository";
import { DataUnavailable, type Carrier } from "@/domain/models";
import type { RequestClient } from "./server";
import type { Database } from "./database.types";
type Row = Database["Basic_Carrier_Record"]["Tables"]["MASTER_Carrier_Contact"]["Row"];
const map = (row: Row): Carrier => ({ iata: row.Carrier_IATA, name: row.Carrier_Name, icao: row.Carrier_ICAO });
export function createCarrierAdapter(client: RequestClient): CarrierRepository {
  const table = () => client.schema("Basic_Carrier_Record").from("MASTER_Carrier_Contact");
  return {
    async listAuthorised() {
      const carriers: Carrier[] = [];
      // Paginate to avoid silently losing authorised carriers at the API row limit.
      const pageSize = 100;
      for (let offset = 0; ; offset += pageSize) {
        const { data, error } = await table().select("Carrier_IATA,Carrier_Name,Carrier_ICAO").order("Carrier_IATA").range(offset, offset + pageSize - 1);
        if (error) throw new DataUnavailable("Unable to load authorised carriers.");
        carriers.push(...data.map(map));
        if (data.length < pageSize) return carriers;
      }
    },
    async findAuthorised(iata) {
      const { data, error } = await table().select("Carrier_IATA,Carrier_Name,Carrier_ICAO").eq("Carrier_IATA", iata).maybeSingle();
      if (error) throw new DataUnavailable("Unable to load the selected carrier.");
      return data ? map(data) : null;
    },
  };
}
