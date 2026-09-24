import "server-only";
import { DataUnavailable } from "@/domain/models";
import { ClassConflict, ClassDenied, ClassInvalid, type CarrierClass, type ClassSnapshot } from "@/domain/class-codes";
import type { ClassRepository } from "@/ports/class-repository";
import type { RequestClient } from "./server";
function rows(value: unknown): CarrierClass[] {
  if (!Array.isArray(value)) throw new DataUnavailable();
  return value.map(row => {
    if (!row || typeof row.code !== "string" || typeof row.description !== "string" || !Number.isInteger(row.priority) || row.priority < 1 || row.priority > 4) throw new DataUnavailable();
    return { code: row.code, priority: row.priority, description: row.description };
  });
}
function snapshot(value: unknown): ClassSnapshot {
  if (!value || typeof value !== "object") throw new DataUnavailable();
  const v = value as ClassSnapshot;
  if (typeof v.canView !== "boolean" || typeof v.canEdit !== "boolean" || typeof v.revision !== "string") throw new DataUnavailable();
  return { canView: v.canView, canEdit: v.canEdit, revision: v.revision, rows: rows(v.rows), defaults: rows(v.defaults) };
}
export function createClassAdapter(client: RequestClient): ClassRepository {
  return {
    async get(iata) {
      const { data, error } = await client.schema("Basic_Carrier_Record").rpc("get_carrier_class_codes", { p_iata: iata });
      if (error) throw new DataUnavailable("Unable to load class codes.");
      return snapshot(data);
    },
    async save(iata, revision, values) {
      const { data, error } = await client.schema("Basic_Carrier_Record").rpc("save_carrier_class_codes", { p_iata: iata, p_revision: revision, p_rows: values });
      if (error?.code === "42501") throw new ClassDenied();
      if (error?.code === "40001") throw new ClassConflict();
      if (error?.code === "23503") throw new ClassInvalid("Complete and save Carrier Details before setting up classes.");
      if (error?.code === "22023" || error?.code === "23514") throw new ClassInvalid("Check the class codes, priorities and descriptions, then try again.");
      if (error) throw new DataUnavailable();
      return snapshot(data);
    },
  };
}
