import type { IndexPerWeightUnitFormula } from "@/domain/index-per-weight-unit";
import{applyFuelConfigurationOverride,appliesToFuelConfiguration,validateFuelConfigurationScope,type FuelConfigurationOption,type FuelConfigurationScoped}from"@/domain/fuel-configuration-scope";

export type AircraftD2DeckType = { code: string; name: string };
export type AircraftD2Area = FuelConfigurationScoped&{ id: string; maxWeight: number | null; maxVolume: number | null; indexPerWeightUnit: number | null };
export type AircraftD2Compartment = FuelConfigurationScoped&{ id: string; areas: AircraftD2Area[] };
export type AircraftD2HoldRow = {
  id?: string;
  sortBalanceArm?: number | null;
  hasDoor?: boolean | null;
  name: string; holdType: "BLK" | "ULD"; deckCode: string; maxWeight: number | null; maxVolume: number | null;
  lateralCentroid: number | null; lateralFrom: number | null; lateralTo: number | null;
  balanceCentroid: number | null; balanceFrom: number | null; balanceTo: number | null;
  indexPerWeightUnit: number | null; compartments: AircraftD2Compartment[];
}&FuelConfigurationScoped;
export type AircraftD2Snapshot = {
  canView: boolean; canEdit: boolean; revision: string; typeCode: string; subtype: string;
  bulkApplicable: boolean | null; uldApplicable: boolean | null; bulkBalanceLimitsRequired: boolean; uldBalanceLimitsRequired: boolean;
  rows: AircraftD2HoldRow[]; deckTypes: AircraftD2DeckType[]; fuelConfigurations?:FuelConfigurationOption[]; balanceFormula?: IndexPerWeightUnitFormula | null;
};
export type AircraftD2Section = "BULK" | "ULD";
export type AircraftD2SectionValues = { applicable: boolean; balanceLimitsRequired: boolean; rows: AircraftD2HoldRow[] };
export type AircraftD2ImportValues = { bulk: AircraftD2SectionValues | null; uld: AircraftD2SectionValues | null };
export class AircraftD2Invalid extends Error {}
export class AircraftD2Denied extends Error {}
export class AircraftD2Conflict extends Error {}
export const bulkHoldNames=["FWD","AFT","FLF","FLA","FLM","ALF","ALA","ALM","ALB"] as const;
export const validBulkHoldName=(value:string)=>(bulkHoldNames as readonly string[]).includes(value);
export const bulkHoldIdentity=(value:string)=>{
 const code=value.trim().toUpperCase();
 if(["FLF","FLM","FLA"].includes(code))return{holdId:"FWD",subCode:code};
 if(["ALF","ALM","ALA"].includes(code))return{holdId:"AFT",subCode:code};
 return{holdId:code,subCode:""};
};
export const resolveBulkHoldName=(holdId:string,subCode:string)=>{
 const parent=holdId.trim().toUpperCase(),child=subCode.trim().toUpperCase();
 if(parent==="FWD"&&(!child||["FLF","FLM","FLA"].includes(child)))return child||parent;
 if(parent==="AFT"&&(!child||["ALF","ALM","ALA"].includes(child)))return child||parent;
 if(parent==="ALB"&&!child)return parent;
 return null;
};
const validateD2FuelScope=<T extends FuelConfigurationScoped>(value:T,options:FuelConfigurationOption[])=>{try{return validateFuelConfigurationScope(value,options)}catch(error){throw new AircraftD2Invalid(error instanceof Error?error.message:"Check the fitted fuel configuration scope.")}};

export const aircraftD2HoldId = (row: Pick<AircraftD2HoldRow, "id" | "deckCode" | "name">) =>
  row.id?.trim() || row.name.trim().toUpperCase();

export const holdDisplayName = (holdId: string) => holdId.includes(":") ? holdId.slice(holdId.lastIndexOf(":") + 1) : holdId;
export const holdDeckCode = (holdId: string) => holdId.includes(":") ? holdId.slice(0, holdId.lastIndexOf(":")) : null;
export const holdDisplayLabel = (holdId: string) => {
  const deck = holdDeckCode(holdId);
  return deck ? `${holdDisplayName(holdId)} — ${deck}` : holdDisplayName(holdId);
};

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

export function validateAircraftD2Section(section: AircraftD2Section, input: unknown, deckTypes: AircraftD2DeckType[],fuelConfigurations:FuelConfigurationOption[]=[]): AircraftD2SectionValues {
  const value = input as { applicable?: unknown; balanceLimitsRequired?: unknown; rows?: unknown };
  if (typeof value?.applicable !== "boolean" || typeof value.balanceLimitsRequired !== "boolean" || !Array.isArray(value.rows)) throw new AircraftD2Invalid("Check the D2 section values.");
  const balanceLimitsRequired = false, applicable = value.applicable;
  if (!applicable) {
    if (value.rows.length) throw new AircraftD2Invalid("Remove the hold rows before marking this section not applicable.");
    return { applicable: false, balanceLimitsRequired, rows: [] };
  }
  if (!value.rows.length) throw new AircraftD2Invalid("Add at least one complete hold row.");
  const identities = new Set<string>(), decks = new Set(deckTypes.map(deck => deck.code));
  const holdType: AircraftD2HoldRow["holdType"] = section === "BULK" ? "BLK" : "ULD";
  const rows = value.rows.map((raw, index) => {
    const row = raw as Partial<AircraftD2HoldRow>, name = String(row.name ?? "").trim().toUpperCase(), deckCode = String(row.deckCode ?? "").trim().toUpperCase();
    if (holdType === "ULD" ? !/^[A-Z]{3}$/.test(name) : !validBulkHoldName(name)) {
      throw new AircraftD2Invalid(holdType === "ULD"
        ? `Row ${index + 1}: enter a three-letter ULD Hold Name.`
        : `Row ${index + 1}: select an approved three-character Bulk Hold ID.`);
    }
    if (!decks.has(deckCode)) throw new AircraftD2Invalid(`Row ${index + 1}: select a valid Deck.`);
    const identity = `${deckCode}:${name}`;
    if (identities.has(identity)) throw new AircraftD2Invalid(`Hold Name ${name} is duplicated on ${deckTypes.find(deck => deck.code === deckCode)?.name ?? deckCode}.`);
    identities.add(identity);
    const maxWeight = finite(row.maxWeight, "Maximum Weight", true);
    const maxVolume = optionalPositive(row.maxVolume, "Maximum Volume");
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
        return validateD2FuelScope({ id: areaId, maxWeight: finite(area.maxWeight, `Maximum Weight for Area ${areaId}`, true), maxVolume: optionalPositive(area.maxVolume, `Volume for Area ${areaId}`), indexPerWeightUnit: finite(area.indexPerWeightUnit, `Index per Weight Unit for Area ${areaId}`),configurationCodes:area.configurationCodes,configurationOverrides:area.configurationOverrides },fuelConfigurations);
      });
      return validateD2FuelScope({ id, areas,configurationCodes:rawCompartment.configurationCodes,configurationOverrides:rawCompartment.configurationOverrides },fuelConfigurations);
    });
    const [balanceCentroid, balanceFrom, balanceTo] = balanceArm(row.balanceCentroid, row.balanceFrom, row.balanceTo);
    const resolvedCompartments = holdType === "BLK" && maxVolume !== null ? calculateMissingAreaVolumes(compartments, maxVolume) : compartments;
    if (row.hasDoor !== null && row.hasDoor !== undefined && typeof row.hasDoor !== "boolean") throw new AircraftD2Invalid(`Row ${index + 1}: select whether the Hold has a door.`);
    return validateD2FuelScope({ id: identity, name, holdType, deckCode, hasDoor: row.hasDoor ?? null, maxWeight, maxVolume, lateralCentroid: row.lateralCentroid ?? null, lateralFrom: row.lateralFrom ?? null, lateralTo: row.lateralTo ?? null, balanceCentroid, balanceFrom, balanceTo, indexPerWeightUnit: finite(row.indexPerWeightUnit, "Index per Weight Unit"), compartments: resolvedCompartments,configurationCodes:row.configurationCodes,configurationOverrides:row.configurationOverrides },fuelConfigurations);
  });
  return { applicable: true, balanceLimitsRequired, rows };
}
export function effectiveAircraftD2Snapshot(snapshot:AircraftD2Snapshot,configurationCode:string|null):AircraftD2Snapshot{
 if(!configurationCode)return snapshot;
 const rows=snapshot.rows.filter(row=>appliesToFuelConfiguration(row,configurationCode)).map(raw=>{
  const row=applyFuelConfigurationOverride(raw,configurationCode);
  return{...row,compartments:row.compartments.filter(compartment=>appliesToFuelConfiguration(compartment,configurationCode)).map(compartment=>({...compartment,areas:compartment.areas.filter(area=>appliesToFuelConfiguration(area,configurationCode)).map(area=>applyFuelConfigurationOverride(area,configurationCode))}))};
 });
 return{...snapshot,rows,bulkApplicable:snapshot.bulkApplicable===false?false:rows.some(row=>row.holdType==="BLK"),uldApplicable:snapshot.uldApplicable===false?false:rows.some(row=>row.holdType==="ULD")};
}
