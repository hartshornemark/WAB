import type { FreightLoadItem, FreightSpecialLoadOption } from "@/domain/freight-acceptance";
import type { LoadPlanningProblem, LoadPlanningSolution } from "@/domain/load-planning-solver";

export type OperationalNotocCategory = "DANGEROUS_GOODS" | "SPECIAL_LOAD";
export type OperationalNotocDetail = {
  key: string;
  loadId: string;
  code: string;
  category: OperationalNotocCategory;
  airwayBillNumber: string;
  properShippingName: string;
  unIdNumber: string;
  classDivision: string;
  subsidiaryRisk: string;
  packingGroup: string;
  numberOfPackages: number | null;
  netQuantityPerPackage: string;
  radioactiveCategory: string;
  cargoAircraftOnly: boolean;
  ergCode: string;
  contentsDescription: string;
  temperatureRequirement: string;
  otherInformation: string;
};

export type OperationalNotocRow = OperationalNotocDetail & {
  stationOfUnloading: string;
  uldId: string | null;
  position: string;
};

export type OperationalDocuments = {
  loadPlanStatus: "DRAFT" | "FINAL";
  finalLoadPlanEdition: number | null;
  loadPlanFinalisedAt: string | null;
  notocVersion: number;
  notocStatus: "EMPTY" | "DRAFT" | "FINAL" | "NOT_REQUIRED";
  notocDetails: OperationalNotocDetail[];
  notocReleasedAt: string | null;
  loadsheetNumber: number;
  loadsheetStatus: "EMPTY" | "FINAL";
  loadsheetSnapshot: OperationalLoadsheetSnapshot | null;
  loadsheetProducedAt: string | null;
};

export type OperationalLoadsheetSnapshot = {
  loadPlanEdition: number;
  fuelPlanVersion: number;
  weights: { zfw: number; ramp: number; tow: number; law: number };
  maximumWeights: { zfw: number; ramp: number; tow: number; law: number };
  dryOperatingWeight: number;
  crewComplement?: string | null;
  fuel: { block: number; taxi: number; takeOff: number; trip: number; landing: number };
  distribution: Array<{ location: string; weight: number }>;
  loadMessage: string[];
  balance: Partial<Record<"DOI" | "DLI" | "LIZFW" | "MACZFW" | "LITOW" | "MACTOW" | "LILAW" | "MACLAW", number>>;
  balanceOutputCodes?: string[];
  trafficLoad: number;
  allowedTrafficLoad: number;
  underload: number;
  limitingWeight?: "ZFW" | "TOW" | "LAW" | null;
  producedAt?: string;
};

export class OperationalDocumentInvalid extends Error {}

const loadsheetHold = (position:LoadPlanningProblem["positions"][number]) => {
  const location=position.locationRef?.trim().toUpperCase()??"",numericLocation=/^([1-5])/.exec(location);
  if(numericLocation)return numericLocation[1];
  const groupCompartment=/([1-5])$/.exec(position.simplicityGroup.trim().toUpperCase());
  if(groupCompartment)return groupCompartment[1];
  const hold=position.holdId.trim().toUpperCase(),numericHold=/^(?:HOLD\s*)?([1-5])$/.exec(hold);
  return numericHold?.[1]??hold;
};

const loadsheetHoldOrder = (value: string) => /^[1-5]$/.test(value)?Number(value):100;

export function operationalLoadsheetDistribution(problem: LoadPlanningProblem, solution: LoadPlanningSolution) {
  const loads = new Map(problem.loads.map(row => [row.id, row])), positions = new Map(problem.positions.map(row => [row.id, row])), totals = new Map<string, number>();
  const configuredHolds=[...new Set(problem.positions.map(loadsheetHold))];
  if(configuredHolds.some(hold=>/^[1-5]$/.test(hold)))for(let hold=1;hold<=5;hold++)totals.set(String(hold),0);
  for(const hold of configuredHolds)totals.set(hold,0);
  for (const assignment of solution.assignments) {
    const load = loads.get(assignment.loadId), position = positions.get(assignment.positionId);
    if (!load || !position) continue;
    const location = loadsheetHold(position);
    totals.set(location, (totals.get(location) ?? 0) + load.weightKg);
  }
  return [...totals].map(([location, weight]) => ({ location, weight })).sort((left, right) => loadsheetHoldOrder(left.location) - loadsheetHoldOrder(right.location) || left.location.localeCompare(right.location,undefined,{numeric:true}));
}

const text = (value: unknown, maximum = 120) => String(value ?? "").trim().slice(0, maximum);
const code = (value: unknown) => text(value, 12).toUpperCase();
const detailKey = (loadId: string, value: string) => `${loadId}:${value}`;

export function notocRequired(items: readonly FreightLoadItem[]) {
  return items.some(item => item.dangerousGoods || item.includedLoads.length > 0 || item.specialHandlingCodes.length > 0);
}

export function notocReadyForLoadsheet(items: readonly FreightLoadItem[], status: OperationalDocuments["notocStatus"]) {
  return notocRequired(items) ? status === "FINAL" : status === "FINAL" || status === "NOT_REQUIRED";
}

export function operationalNotocDisplayStatus(required:boolean,status:OperationalDocuments["notocStatus"],dirty:boolean,attentionCount:number){
 if(!required)return"NOT REQUIRED";
 if(status==="FINAL")return dirty?"FINAL · UNSAVED EDITS":"FINAL";
 if(attentionCount>0)return`REQUIRED · ${attentionCount} ATTENTION`;
 return status==="DRAFT"&&!dirty?"DRAFT · READY":"REQUIRED · READY";
}

export function operationalNotocDetailComplete(row:OperationalNotocDetail){
 if(row.category==="DANGEROUS_GOODS")return Boolean(row.airwayBillNumber&&row.properShippingName&&row.unIdNumber&&row.classDivision&&row.numberOfPackages&&row.netQuantityPerPackage&&row.ergCode&&(!/^RR|^RX/.test(row.code)||row.radioactiveCategory));
 return Boolean(row.contentsDescription&&row.numberOfPackages);
}

export function seedOperationalNotocDetails(items: readonly FreightLoadItem[], options: readonly FreightSpecialLoadOption[], saved: readonly OperationalNotocDetail[] = []) {
  const prior = new Map(saved.map(row => [row.key, row]));
  const result: OperationalNotocDetail[] = [];
  for (const item of items) {
    const included = new Map(item.includedLoads.map(row => [row.code, row]));
    const codes = [...new Set([...item.specialHandlingCodes, ...item.includedLoads.map(row => row.code)])];
    for (const specialCode of codes) {
      const option = options.find(row => row.code === specialCode), dangerous = included.get(specialCode)?.dangerousGoods ?? option?.dangerousGoods ?? false;
      const key = detailKey(item.lineId, specialCode), existing = prior.get(key),knownClass=(option?.classes??[]).join("/");
      const seeded:OperationalNotocDetail={
        key, loadId: item.lineId, code: specialCode, category: dangerous ? "DANGEROUS_GOODS" : "SPECIAL_LOAD",
        airwayBillNumber: "", properShippingName: "", unIdNumber: "", classDivision: dangerous?knownClass:"", subsidiaryRisk: "", packingGroup: "",
        numberOfPackages: item.pieces, netQuantityPerPackage: included.has(specialCode) ? `${included.get(specialCode)!.weight} KG` : "",
        radioactiveCategory: "", cargoAircraftOnly: option?.cargoAircraftOnly ?? false, ergCode: "",
        contentsDescription: option?.description ?? item.remarks ?? "", temperatureRequirement: "", otherInformation: "",
      };
      result.push(existing?{...seeded,...existing,classDivision:existing.classDivision||seeded.classDivision}:seeded);
    }
  }
  return result;
}

export function validateOperationalNotocDetails(value: unknown, items: readonly FreightLoadItem[], options: readonly FreightSpecialLoadOption[], finalise: boolean) {
  if (!Array.isArray(value)) throw new OperationalDocumentInvalid("The NOTOC details are incomplete.");
  const seeded = seedOperationalNotocDetails(items, options, value as OperationalNotocDetail[]);
  const incoming = new Map((value as OperationalNotocDetail[]).map(row => [text(row?.key, 100), row]));
  const rows = seeded.map(seed => {
    const raw = incoming.get(seed.key) ?? seed, rawPackages: unknown = raw.numberOfPackages, packages = rawPackages === null || rawPackages === undefined || rawPackages === "" ? null : Number(rawPackages);
    if (packages !== null && (!Number.isSafeInteger(packages) || packages < 1)) throw new OperationalDocumentInvalid(`${seed.code} requires a valid number of packages.`);
    const row: OperationalNotocDetail = {
      ...seed,
      airwayBillNumber: text(raw.airwayBillNumber, 35), properShippingName: text(raw.properShippingName, 180), unIdNumber: code(raw.unIdNumber),
      classDivision: code(raw.classDivision), subsidiaryRisk: code(raw.subsidiaryRisk), packingGroup: code(raw.packingGroup), numberOfPackages: packages,
      netQuantityPerPackage: text(raw.netQuantityPerPackage, 80), radioactiveCategory: text(raw.radioactiveCategory, 40), cargoAircraftOnly: Boolean(raw.cargoAircraftOnly),
      ergCode: code(raw.ergCode), contentsDescription: text(raw.contentsDescription, 220), temperatureRequirement: text(raw.temperatureRequirement, 80), otherInformation: text(raw.otherInformation, 300),
    };
    if (finalise && row.category === "DANGEROUS_GOODS") {
      const missing = [[row.airwayBillNumber, "airway bill number"], [row.properShippingName, "proper shipping name"], [row.unIdNumber, "UN or ID number"], [row.classDivision, "class or division"], [row.numberOfPackages, "number of packages"], [row.netQuantityPerPackage, "net quantity"], [row.ergCode, "ERG code"]].filter(([entry]) => !entry).map(([, label]) => label);
      if (missing.length) throw new OperationalDocumentInvalid(`${row.code} requires ${missing.join(", ")} before the NOTOC can be finalised.`);
      if (/^RR|^RX/.test(row.code) && !row.radioactiveCategory) throw new OperationalDocumentInvalid(`${row.code} requires its radioactive category before the NOTOC can be finalised.`);
    }
    if (finalise && row.category === "SPECIAL_LOAD") {
      const missing = [[row.contentsDescription, "contents and description"], [row.numberOfPackages, "number of packages"]].filter(([entry]) => !entry).map(([, label]) => label);
      if (missing.length) throw new OperationalDocumentInvalid(`${row.code} requires ${missing.join(" and ")} before the NOTOC can be finalised.`);
    }
    return row;
  });
  if (finalise && notocRequired(items) && !rows.length) throw new OperationalDocumentInvalid("Complete the NOTOC entries before finalising it.");
  return rows;
}

export function operationalNotocRows(input: { details: readonly OperationalNotocDetail[]; items: readonly FreightLoadItem[]; problem: LoadPlanningProblem; solution: LoadPlanningSolution }) {
  const assignments = new Map(input.solution.assignments.map(row => [row.loadId, row.positionId])), positions = new Map(input.problem.positions.map(row => [row.id, row]));
  return input.details.map(detail => {
    const item = input.items.find(row => row.lineId === detail.loadId), position = positions.get(assignments.get(detail.loadId) ?? "");
    if (!item || !position) throw new OperationalDocumentInvalid(`The load-plan location for ${detail.code} is unavailable.`);
    return { ...detail, stationOfUnloading: item.unloadingStation, uldId: item.uldId, position: position.locationRef ?? position.description } satisfies OperationalNotocRow;
  });
}

export function orderOperationalNotocRows(rows:readonly OperationalNotocRow[],problem:LoadPlanningProblem){
 const unloadOrder=new Map(problem.loads.map(load=>[load.id,load.unloadOrder]));
 return[...rows].sort((left,right)=>(unloadOrder.get(left.loadId)??Number.MAX_SAFE_INTEGER)-(unloadOrder.get(right.loadId)??Number.MAX_SAFE_INTEGER)||left.stationOfUnloading.localeCompare(right.stationOfUnloading,"en",{numeric:true})||left.position.localeCompare(right.position,"en",{numeric:true})||left.code.localeCompare(right.code,"en",{numeric:true}));
}
