import type { IndexPerWeightUnitFormula } from "@/domain/index-per-weight-unit";

export type AircraftD2DeckType = { code: string; name: string };
export type AircraftD2Area = { id: string; maxWeight: number | null; maxVolume: number | null; indexPerWeightUnit: number | null };
export type AircraftD2Compartment = { id: string; areas: AircraftD2Area[] };
export type AircraftD2HoldRow = {
  name: string; holdType: "BLK" | "ULD"; deckCode: string; maxWeight: number | null; maxVolume: number | null;
  lateralCentroid: number | null; lateralFrom: number | null; lateralTo: number | null;
  balanceCentroid: number | null; balanceFrom: number | null; balanceTo: number | null;
  indexPerWeightUnit: number | null; compartments: AircraftD2Compartment[];
};
export type AircraftD2Snapshot = {
  canView: boolean; canEdit: boolean; revision: string; typeCode: string; subtype: string;
  bulkApplicable: boolean | null; uldApplicable: boolean | null; bulkBalanceLimitsRequired: boolean; uldBalanceLimitsRequired: boolean;
  rows: AircraftD2HoldRow[]; deckTypes: AircraftD2DeckType[]; balanceFormula?: IndexPerWeightUnitFormula | null;
};
export type AircraftD2Section = "BULK" | "ULD";
export type AircraftD2SectionValues = { applicable: boolean; balanceLimitsRequired: boolean; rows: AircraftD2HoldRow[] };
export class AircraftD2Invalid extends Error {}
export class AircraftD2Denied extends Error {}
export class AircraftD2Conflict extends Error {}

const finite = (value: unknown, label: string, positive = false) => {
  const number = typeof value === "number" ? value : Number(value);
  if (value === null || value === "" || typeof value === "boolean" || !Number.isFinite(number) || Math.abs(number) > 1e9 || (positive && number <= 0)) throw new AircraftD2Invalid(`Enter a valid ${label}.`);
  return number;
};
const optionalPositive = (value: unknown, label: string) => value === null || value === "" ? null : finite(value, label, true);
const roundVolume = (value: number) => Math.round((value + Number.EPSILON) * 100) / 100;
export function calculateMissingAreaVolumes(compartments: AircraftD2Compartment[], holdVolume: number) {
  const allAreas = compartments.flatMap(compartment => compartment.areas);
  const missing = allAreas.filter(area => area.maxVolume === null);
  if (!missing.length) return compartments;
  const totalWeight = allAreas.reduce((total, area) => total + (area.maxWeight ?? 0), 0);
  if (totalWeight <= 0) throw new AircraftD2Invalid("Area Volume cannot be calculated without Area Maximum Weight values.");
  const allMissing = missing.length === allAreas.length;
  let allocated = 0;
  let missingIndex = 0;
  return compartments.map(compartment => ({
    ...compartment,
    areas: compartment.areas.map(area => {
      if (area.maxVolume !== null) return area;
      missingIndex += 1;
      const calculated = allMissing && missingIndex === missing.length ? roundVolume(holdVolume - allocated) : roundVolume(holdVolume * (area.maxWeight ?? 0) / totalWeight);
      allocated = roundVolume(allocated + calculated);
      return { ...area, maxVolume: calculated };
    }),
  }));
}
const balanceArm = (centroid: unknown, from: unknown, to: unknown) => {
  const blank = (value: unknown) => value === null || value === "";
  const c = blank(centroid) ? null : finite(centroid, "Balance Arm Centroid");
  if (blank(from) && blank(to)) return [c, null, null] as const;
  if (blank(from) || blank(to)) throw new AircraftD2Invalid("Complete both Balance Arm From and To values, or leave both blank.");
  const f = finite(from, "Balance Arm From"), t = finite(to, "Balance Arm To");
  if (f > t || (c !== null && (f > c || c > t))) throw new AircraftD2Invalid("Balance Arm must be ordered From, Centroid, To when those values are supplied.");
  return [c, f, t] as const;
};

export function validateAircraftD2Section(section: AircraftD2Section, input: unknown, deckTypes: AircraftD2DeckType[]): AircraftD2SectionValues {
  const value = input as { applicable?: unknown; balanceLimitsRequired?: unknown; rows?: unknown };
  if (typeof value?.applicable !== "boolean" || typeof value.balanceLimitsRequired !== "boolean" || !Array.isArray(value.rows)) throw new AircraftD2Invalid("Check the D2 section values.");
  const balanceLimitsRequired = false, applicable = value.applicable;
  if (!applicable) {
    if (value.rows.length) throw new AircraftD2Invalid("Remove the hold rows before marking this section not applicable.");
    return { applicable: false, balanceLimitsRequired, rows: [] };
  }
  if (!value.rows.length) throw new AircraftD2Invalid("Add at least one complete hold row.");
  const names = new Set<string>(), decks = new Set(deckTypes.map(deck => deck.code));
  const holdType: AircraftD2HoldRow["holdType"] = section === "BULK" ? "BLK" : "ULD";
  const rows = value.rows.map((raw, index) => {
    const row = raw as Partial<AircraftD2HoldRow>, name = String(row.name ?? "").trim().toUpperCase(), deckCode = String(row.deckCode ?? "").trim().toUpperCase();
    if (holdType === "ULD" ? !/^[A-Z]{3}$/.test(name) : !/^[A-Z0-9]$/.test(name)) {
      throw new AircraftD2Invalid(holdType === "ULD"
        ? `Row ${index + 1}: enter a three-letter ULD Hold Name.`
        : `Row ${index + 1}: enter a one-character Hold Name.`);
    }
    if (names.has(name)) throw new AircraftD2Invalid(`Hold Name ${name} is duplicated.`);
    names.add(name);
    if (!decks.has(deckCode)) throw new AircraftD2Invalid(`Row ${index + 1}: select a valid Deck.`);
    const maxWeight = finite(row.maxWeight, "Maximum Weight", true);
    const maxVolume = holdType === "ULD"
      ? optionalPositive(row.maxVolume, "Maximum Volume")
      : finite(row.maxVolume, "Maximum Volume", true);
    if (!Array.isArray(row.compartments)) throw new AircraftD2Invalid(`Hold ${name}: check its compartments.`);
    const compartmentIds = new Set<string>();
    const compartments = row.compartments.map((rawCompartment, compartmentIndex) => {
      const id = String(rawCompartment?.id ?? "").trim().toUpperCase();
      if (!/^[A-Z0-9]{1,3}$/.test(id)) throw new AircraftD2Invalid(`Hold ${name}, Compartment ${compartmentIndex + 1}: enter 1–3 letters or numbers.`);
      if (compartmentIds.has(id)) throw new AircraftD2Invalid(`Hold ${name}: Compartment ${id} is duplicated.`);
      compartmentIds.add(id);
      if (!Array.isArray(rawCompartment.areas)) throw new AircraftD2Invalid(`Hold ${name}, Compartment ${id}: check its Areas.`);
      if (holdType === "ULD" && rawCompartment.areas.length) throw new AircraftD2Invalid(`Hold ${name}, Compartment ${id}: ULD compartments use Bays configured on D3, not Areas.`);
      const areaIds = new Set<string>();
      const areas = rawCompartment.areas.map((rawArea, areaIndex) => {
        const area = rawArea as Partial<AircraftD2Area>, areaId = String(area?.id ?? "").trim().toUpperCase();
        if (!/^[A-Z0-9]{1,3}$/.test(areaId)) throw new AircraftD2Invalid(`Hold ${name}, Compartment ${id}, Area ${areaIndex + 1}: enter 1–3 letters or numbers.`);
        if (areaIds.has(areaId)) throw new AircraftD2Invalid(`Hold ${name}, Compartment ${id}: Area ${areaId} is duplicated.`);
        areaIds.add(areaId);
        return { id: areaId, maxWeight: finite(area.maxWeight, `Maximum Weight for Area ${areaId}`, true), maxVolume: optionalPositive(area.maxVolume, `Volume for Area ${areaId}`), indexPerWeightUnit: finite(area.indexPerWeightUnit, `Index per Weight Unit for Area ${areaId}`) };
      });
      return { id, areas };
    });
    const [balanceCentroid, balanceFrom, balanceTo] = balanceArm(row.balanceCentroid, row.balanceFrom, row.balanceTo);
    return { name, holdType, deckCode, maxWeight, maxVolume, lateralCentroid: row.lateralCentroid ?? null, lateralFrom: row.lateralFrom ?? null, lateralTo: row.lateralTo ?? null, balanceCentroid, balanceFrom, balanceTo, indexPerWeightUnit: finite(row.indexPerWeightUnit, "Index per Weight Unit"), compartments: holdType === "BLK" ? calculateMissingAreaVolumes(compartments, maxVolume as number) : compartments };
  });
  return { applicable: true, balanceLimitsRequired, rows };
}
