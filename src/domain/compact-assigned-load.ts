import type { SolverLoad } from "./load-planning-solver";

/** Split a recognised ULD identity without shortening or fabricating its serial. */
export function compactUldIdentityParts(identity: string, uldCode: string | null) {
  if (!uldCode || !identity.startsWith(uldCode)) return null;
  const serial = identity.slice(uldCode.length);
  return /^[0-9][A-Z0-9]*$/i.test(serial) ? { type: uldCode, serial } : null;
}

/** Display fields only; never creates a ULD number or changes placement data. */
export function compactAssignedLoadFields(load: SolverLoad, loadReference?: string | null) {
  const described = load.description.split(" · ")[0]?.trim();
  const numberedBaggage = /^PLANNED_BAGGAGE:\d+$/.test(load.id);
  const uldIdentity = numberedBaggage && (!described || described === load.uldCode || /^(?:BF|BJ|BP|BY|B) BAGGAGE \d+\/\d+$/.test(described)) ? null : described;
  const bulkCode = load.commodityCode ?? load.specialLoadCodes.find(code => code !== "BAG") ?? load.commodity ?? "BULK";
  const identity = loadReference?.trim() || (load.loadType === "BULK" ? `${bulkCode}${bulkCode === "BULK" ? "" : " BULK"}` : uldIdentity) || load.id;
  return { identity, destination: load.description.split("unload ")[1]?.trim() || "—", weight: `${Math.round(load.weightKg).toLocaleString("en-GB")} KG` };
}
