export type CapacityPosition = {
  id: string;
  kind: "PALLET" | "CONTAINER";
  occupiedBayIds: string[];
  maximumNetWeightGrams: number;
};
export type CargoCapacityProblem = {
  mode: "CARGO_CAPACITY";
  aircraftType: "359";
  inputRevision: string;
  baggageUldCount: number;
  timeLimitSeconds: number;
  positions: CapacityPosition[];
};
export type CapacityArrangement = {
  palletPositionIds: string[];
  containerPositionIds: string[];
  baggagePositionIds: string[];
  cargoNetWeightGrams: number;
};
export type CargoCapacityResult = {
  mode: "CARGO_CAPACITY";
  aircraftType: "359";
  inputRevision: string;
  status: "OPTIMAL" | "FEASIBLE" | "INFEASIBLE" | "UNKNOWN";
  engine: "OR-TOOLS CP-SAT";
  provedObjectives: string[];
  solveMilliseconds: number;
  arrangement: CapacityArrangement | null;
};
const token = (value: unknown): value is string => typeof value === "string" && value.trim().length > 0 && value.length <= 256;
const integer = (value: unknown, maximum: number): value is number => typeof value === "number" && Number.isSafeInteger(value) && value >= 0 && value <= maximum;
const invalid = () => { throw new Error("Invalid cargo-capacity input or solver result."); };

export function validateCargoCapacityProblem(value: unknown): CargoCapacityProblem {
  const p = value as CargoCapacityProblem;
  if (!p || p.mode !== "CARGO_CAPACITY" || p.aircraftType !== "359" || !token(p.inputRevision) || !integer(p.baggageUldCount, 500) || !Number.isFinite(p.timeLimitSeconds) || p.timeLimitSeconds <= 0 || p.timeLimitSeconds > 10 || !Array.isArray(p.positions) || p.positions.length > 500) invalid();
  const seen = new Set<string>();
  for (const row of p.positions) {
    if (!row || !token(row.id) || seen.has(row.id) || !["PALLET", "CONTAINER"].includes(row.kind) || !integer(row.maximumNetWeightGrams, 100_000_000) || !Array.isArray(row.occupiedBayIds) || row.occupiedBayIds.length < 1 || row.occupiedBayIds.length > 100 || row.occupiedBayIds.some(bay => !token(bay)) || new Set(row.occupiedBayIds).size !== row.occupiedBayIds.length) invalid();
    seen.add(row.id);
  }
  return p;
}

/** Validate the returned witness independently of CP-SAT. No placement is saved. */
export function validateCargoCapacityResult(problem: CargoCapacityProblem, value: unknown): CargoCapacityResult {
  validateCargoCapacityProblem(problem);
  const r = value as CargoCapacityResult;
  const priorities = ["PALLETS", "CONTAINERS", "NET_WEIGHT"];
  if (!r || r.mode !== problem.mode || r.aircraftType !== problem.aircraftType || r.inputRevision !== problem.inputRevision || r.engine !== "OR-TOOLS CP-SAT" || !["OPTIMAL", "FEASIBLE", "INFEASIBLE", "UNKNOWN"].includes(r.status) || !integer(r.solveMilliseconds, 60_000) || !Array.isArray(r.provedObjectives) || r.provedObjectives.length > 3 || r.provedObjectives.some((v, i) => v !== priorities[i])) invalid();
  if (r.status === "UNKNOWN" || r.status === "INFEASIBLE") {
    if (r.arrangement !== null || r.provedObjectives.length) invalid();
    return r;
  }
  if ((r.status === "OPTIMAL") !== (r.provedObjectives.length === 3)) invalid();
  const a = r.arrangement;
  if (!a || !Array.isArray(a.palletPositionIds) || !Array.isArray(a.containerPositionIds) || !Array.isArray(a.baggagePositionIds) || a.baggagePositionIds.length !== problem.baggageUldCount || !integer(a.cargoNetWeightGrams, 50_000_000_000)) invalid();
  const positions = new Map(problem.positions.map(p => [p.id, p]));
  const ids = new Set<string>(), bays = new Set<string>();
  let net = 0;
  for (const [group, kind, cargo] of [[a!.palletPositionIds, "PALLET", true], [a!.containerPositionIds, "CONTAINER", true], [a!.baggagePositionIds, "CONTAINER", false]] as const) {
    if (group.length > problem.positions.length) invalid();
    for (const id of group) {
      const p = positions.get(id);
      if (!p || p.kind !== kind || ids.has(id)) invalid();
      ids.add(id);
      for (const bay of p!.occupiedBayIds) {
        if (bays.has(bay)) invalid();
        bays.add(bay);
      }
      if (cargo) net += p!.maximumNetWeightGrams;
    }
  }
  if (net !== a!.cargoNetWeightGrams) invalid();
  return r;
}
