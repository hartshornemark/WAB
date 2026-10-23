export const CARGO_CAPACITY_RULES = "A350_MAX_NET_CARGO_V2" as const;
export type CapacityGroup = { id: string; parentId: string | null; maximumGrossWeightGrams: number; maximumBulkVolumeMillilitres: number | null };
export type CapacityPosition = { id: string; kind: "PALLET" | "CONTAINER"; groupId: string; occupiedBayIds: string[]; tareWeightGrams: number; maximumGrossWeightGrams: number; maximumVolumeMillilitres: number };
export type BulkArea = { id: string; groupId: string; maximumGrossWeightGrams: number; maximumVolumeMillilitres: number };
export type BaggageUld = { id: string; netWeightGrams: number; volumeMillilitres: number; compatiblePositionIds: string[] };
export type FixedCapacityLoad = { id: string; kind: "BAGGAGE_BULK" | "OTHER"; grossWeightGrams: number; bulkVolumeMillilitres: number; bulkAreaId: string | null; groupId: string | null; occupiedBayIds: string[] };
export type CargoCapacityProblem = {
  mode: "CARGO_CAPACITY"; aircraftType: "359"; rulesVersion: typeof CARGO_CAPACITY_RULES; inputRevision: string; timeLimitSeconds: number;
  maximumZeroFuelWeightGrams: number; dryOperatingWeightGrams: number; passengerWeightGrams: number; cargoDensityGramsPerM3: number;
  positions: CapacityPosition[]; groups: CapacityGroup[]; bulkAreas: BulkArea[]; baggageUlds: BaggageUld[]; fixedLoads: FixedCapacityLoad[];
};
export type CapacityArrangement = {
  cargoUlds: { positionId: string; netWeightGrams: number }[];
  baggageUlds: { loadId: string; positionId: string }[];
  bulkCargo: { areaId: string; netWeightGrams: number }[];
  cargoNetWeightGrams: number; cargoTareWeightGrams: number; cargoGrossWeightGrams: number;
};
export type CargoCapacityResult = {
  mode: "CARGO_CAPACITY"; aircraftType: "359"; rulesVersion: typeof CARGO_CAPACITY_RULES; inputRevision: string;
  status: "OPTIMAL" | "FEASIBLE" | "INFEASIBLE" | "UNKNOWN"; engine: "OR-TOOLS CP-SAT"; solveMilliseconds: number; arrangement: CapacityArrangement | null;
};
const token = (v: unknown): v is string => typeof v === "string" && v.trim().length > 0 && v.length <= 256;
const integer = (v: unknown, max = 1_000_000_000): v is number => typeof v === "number" && Number.isSafeInteger(v) && v >= 0 && v <= max;
function invalid(): never { throw new Error("Invalid version-2 cargo-capacity input or solver result."); }
const unique = (values: unknown[]): boolean => new Set(values).size === values.length;
const tokens = (v: unknown, max: number): v is string[] => Array.isArray(v) && v.length <= max && v.every(token) && unique(v);
export function capacityAncestors(id: string, groups: Map<string, CapacityGroup>): string[] {
  const path: string[] = [];
  let next: string | null = id;
  while (next !== null) {
    const g = groups.get(next);
    if (!g || path.includes(next)) invalid();
    path.push(next); next = g.parentId;
  }
  return path;
}
export function validateCargoCapacityProblem(value: unknown): CargoCapacityProblem {
  const p = value as CargoCapacityProblem;
  if (!p || p.mode !== "CARGO_CAPACITY" || p.aircraftType !== "359" || p.rulesVersion !== CARGO_CAPACITY_RULES || !token(p.inputRevision) || !Number.isFinite(p.timeLimitSeconds) || p.timeLimitSeconds <= 0 || p.timeLimitSeconds > 10) invalid();
  for (const v of [p.maximumZeroFuelWeightGrams, p.dryOperatingWeightGrams, p.passengerWeightGrams, p.cargoDensityGramsPerM3]) if (!integer(v)) invalid();
  if (p.cargoDensityGramsPerM3 === 0) invalid();
  for (const [rows, max] of [[p.positions, 500], [p.groups, 100], [p.bulkAreas, 100], [p.baggageUlds, 100], [p.fixedLoads, 500]] as const) {
    if (!Array.isArray(rows) || rows.length > max || rows.some(r => !r || !token(r.id)) || !unique(rows.map(r => r.id))) invalid();
  }
  const groups = new Map(p.groups.map(g => [g.id, g]));
  for (const g of p.groups) {
    if (!(g.parentId === null || token(g.parentId)) || !integer(g.maximumGrossWeightGrams) || !(g.maximumBulkVolumeMillilitres === null || integer(g.maximumBulkVolumeMillilitres))) invalid();
    capacityAncestors(g.id, groups);
  }
  const positions = new Map(p.positions.map(r => [r.id, r]));
  for (const r of p.positions) if (!["PALLET", "CONTAINER"].includes(r.kind) || !groups.has(r.groupId) || !tokens(r.occupiedBayIds, 100) || !r.occupiedBayIds.length || !integer(r.tareWeightGrams) || !integer(r.maximumGrossWeightGrams) || r.tareWeightGrams > r.maximumGrossWeightGrams || !integer(r.maximumVolumeMillilitres)) invalid();
  const areas = new Map(p.bulkAreas.map(r => [r.id, r]));
  for (const a of p.bulkAreas) if (!groups.has(a.groupId) || !integer(a.maximumGrossWeightGrams) || !integer(a.maximumVolumeMillilitres)) invalid();
  for (const b of p.baggageUlds) if (!integer(b.netWeightGrams) || !integer(b.volumeMillilitres) || !tokens(b.compatiblePositionIds, 500) || b.compatiblePositionIds.some(id => positions.get(id)?.kind !== "CONTAINER")) invalid();
  const fixedBays = new Set<string>();
  for (const r of p.fixedLoads) {
    if (!["BAGGAGE_BULK", "OTHER"].includes(r.kind) || !integer(r.grossWeightGrams) || !integer(r.bulkVolumeMillilitres) || !tokens(r.occupiedBayIds, 100)) invalid();
    if (r.bulkAreaId !== null) {
      if (!areas.has(r.bulkAreaId) || r.groupId !== null || r.occupiedBayIds.length) invalid();
    } else if (!groups.has(r.groupId!) || r.kind === "BAGGAGE_BULK" || r.bulkVolumeMillilitres !== 0) invalid();
    for (const bay of r.occupiedBayIds) { if (fixedBays.has(bay)) invalid(); fixedBays.add(bay); }
  }
  return p;
}
/** Validate every resource, reservation and weight/space limit independently. */
export function validateCargoCapacityResult(problem: CargoCapacityProblem, value: unknown): CargoCapacityResult {
  const p = validateCargoCapacityProblem(problem), r = value as CargoCapacityResult;
  if (!r || r.mode !== p.mode || r.aircraftType !== p.aircraftType || r.rulesVersion !== CARGO_CAPACITY_RULES || r.inputRevision !== p.inputRevision || r.engine !== "OR-TOOLS CP-SAT" || !["OPTIMAL", "FEASIBLE", "INFEASIBLE", "UNKNOWN"].includes(r.status) || !integer(r.solveMilliseconds, 60_000)) invalid();
  if (r.status === "UNKNOWN" || r.status === "INFEASIBLE") { if (r.arrangement !== null) invalid(); return r; }
  const a = r.arrangement;
  if (!a || !Array.isArray(a.cargoUlds) || a.cargoUlds.length > p.positions.length || !Array.isArray(a.baggageUlds) || a.baggageUlds.length !== p.baggageUlds.length || !Array.isArray(a.bulkCargo) || a.bulkCargo.length > p.bulkAreas.length) invalid();
  const groups = new Map(p.groups.map(g => [g.id, g])), positions = new Map(p.positions.map(v => [v.id, v])), areas = new Map(p.bulkAreas.map(v => [v.id, v]));
  const groupWeight = new Map(p.groups.map(g => [g.id, 0])), groupBulkWeight = new Map(p.groups.map(g => [g.id, 0])), groupFixedVolume = new Map(p.groups.map(g => [g.id, 0]));
  const areaWeight = new Map(p.bulkAreas.map(v => [v.id, 0])), areaFixedVolume = new Map(p.bulkAreas.map(v => [v.id, 0]));
  let grossTraffic = 0, net = 0, tare = 0;
  const usedBays = new Set<string>(), usedPositions = new Set<string>(), usedBags = new Set<string>(), usedAreas = new Set<string>();
  const add = (group: string, weight: number) => { grossTraffic += weight; for (const id of capacityAncestors(group, groups)) groupWeight.set(id, groupWeight.get(id)! + weight); };
  const claim = (id: string) => {
    const pos = positions.get(id); if (!pos || usedPositions.has(id)) invalid(); usedPositions.add(id);
    for (const bay of pos.occupiedBayIds) { if (usedBays.has(bay)) invalid(); usedBays.add(bay); }
    return pos;
  };
  for (const v of p.fixedLoads) {
    const area = v.bulkAreaId === null ? null : areas.get(v.bulkAreaId)!;
    const group = area ? area.groupId : v.groupId!; add(group, v.grossWeightGrams);
    if (area) { areaWeight.set(area.id, areaWeight.get(area.id)! + v.grossWeightGrams); areaFixedVolume.set(area.id, areaFixedVolume.get(area.id)! + v.bulkVolumeMillilitres); }
    for (const id of capacityAncestors(group, groups)) groupFixedVolume.set(id, groupFixedVolume.get(id)! + v.bulkVolumeMillilitres);
    for (const bay of v.occupiedBayIds) usedBays.add(bay);
  }
  for (const v of a!.baggageUlds) {
    const bag = p.baggageUlds.find(b => b.id === v.loadId); const pos = claim(v.positionId);
    if (!bag || usedBags.has(v.loadId) || !bag.compatiblePositionIds.includes(pos.id) || bag.netWeightGrams + pos.tareWeightGrams > pos.maximumGrossWeightGrams || bag.volumeMillilitres > pos.maximumVolumeMillilitres) invalid();
    usedBags.add(v.loadId); add(pos.groupId, bag.netWeightGrams + pos.tareWeightGrams);
  }
  for (const v of a!.cargoUlds) { const pos = claim(v.positionId); if (!integer(v.netWeightGrams) || v.netWeightGrams <= 0 || v.netWeightGrams + pos.tareWeightGrams > pos.maximumGrossWeightGrams) invalid(); add(pos.groupId, v.netWeightGrams + pos.tareWeightGrams); net += v.netWeightGrams; tare += pos.tareWeightGrams; }
  for (const v of a!.bulkCargo) {
    const area = areas.get(v.areaId); if (!area || usedAreas.has(v.areaId) || !integer(v.netWeightGrams) || v.netWeightGrams <= 0) invalid(); usedAreas.add(v.areaId);
    areaWeight.set(area.id, areaWeight.get(area.id)! + v.netWeightGrams);
    if (BigInt(v.netWeightGrams) * 1_000_000n > BigInt(area.maximumVolumeMillilitres - areaFixedVolume.get(area.id)!) * BigInt(p.cargoDensityGramsPerM3)) invalid();
    add(area.groupId, v.netWeightGrams); net += v.netWeightGrams;
    for (const id of capacityAncestors(area.groupId, groups)) groupBulkWeight.set(id, groupBulkWeight.get(id)! + v.netWeightGrams);
  }
  for (const area of p.bulkAreas) if (areaWeight.get(area.id)! > area.maximumGrossWeightGrams || areaFixedVolume.get(area.id)! > area.maximumVolumeMillilitres) invalid();
  for (const g of p.groups) {
    if (groupWeight.get(g.id)! > g.maximumGrossWeightGrams) invalid();
    if (g.maximumBulkVolumeMillilitres !== null && (groupFixedVolume.get(g.id)! > g.maximumBulkVolumeMillilitres || BigInt(groupBulkWeight.get(g.id)!) * 1_000_000n > BigInt(g.maximumBulkVolumeMillilitres - groupFixedVolume.get(g.id)!) * BigInt(p.cargoDensityGramsPerM3))) invalid();
  }
  if (grossTraffic + p.passengerWeightGrams + p.dryOperatingWeightGrams > p.maximumZeroFuelWeightGrams || a!.cargoNetWeightGrams !== net || a!.cargoTareWeightGrams !== tare || a!.cargoGrossWeightGrams !== net + tare) invalid();
  return r;
}
