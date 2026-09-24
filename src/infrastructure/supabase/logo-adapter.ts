import "server-only";
import { randomUUID } from "node:crypto";
import type { CarrierLogoRepository } from "@/ports/carrier-logo-repository";
import { DataUnavailable } from "@/domain/models";
import type { RequestClient } from "./server";
export function createLogoAdapter(client: RequestClient): CarrierLogoRepository {
  const bucket = () => client.storage.from("carrier-logos");
  const schema = () => client.schema("Basic_Carrier_Record");
  return {
    async getMany(iatas) {
      const result: Record<string, string | null> = {};
      // Small batches also avoid PostgREST's response row limit and long query URLs.
      for (let offset = 0; offset < iatas.length; offset += 100) {
        const { data, error } = await schema().from("Carrier_Branding").select("Carrier_IATA,logo_path").in("Carrier_IATA", iatas.slice(offset, offset + 100));
        if (error) throw new DataUnavailable("Unable to load carrier branding.");
        await Promise.all(data.map(async row => {
          result[row.Carrier_IATA] = null;
          if (!row.logo_path) return;
          const { data: signed, error: signError } = await bucket().createSignedUrl(row.logo_path, 3600);
          if (!signError && signed) result[row.Carrier_IATA] = signed.signedUrl;
        }));
      }
      return result;
    },
    async canManage(iata) {
      const { data, error } = await schema().rpc("can_manage_carrier_logo", { p_iata: iata });
      if (error) throw new DataUnavailable("Unable to check logo permissions.");
      return data === true;
    },
    async upload(iata, image) {
      const path = `${iata}/${randomUUID()}.png`;
      const { error } = await bucket().upload(path, image, { contentType: "image/png", upsert: false, cacheControl: "60" });
      if (error) throw new DataUnavailable("Unable to upload logo.");
      return path;
    },
    async setReference(iata, path) {
      const { data, error } = await schema().rpc("set_carrier_logo", { p_iata: iata, p_path: path });
      if (error) throw new DataUnavailable("Unable to save logo. Refresh before trying again.");
      return data;
    },
    async deleteFile(path) {
      const { error } = await bucket().remove([path]);
      if (error) throw new DataUnavailable("Unable to remove the previous file.");
    },
  };
}
