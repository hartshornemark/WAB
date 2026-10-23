import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { validateCargoCapacityProblem, validateCargoCapacityResult, type CargoCapacityProblem, type CargoCapacityResult } from "../src/domain/cargo-capacity";
import { createCpSatCargoCapacitySolver } from "../src/infrastructure/solver/cp-sat-cargo-capacity-solver";

const problem: CargoCapacityProblem = { mode: "CARGO_CAPACITY", aircraftType: "359", inputRevision: "configuration-1:baggage-2", baggageUldCount: 1, timeLimitSeconds: 1, positions: [
  { id: "pallet", kind: "PALLET", occupiedBayIds: ["FWD:11", "FWD:12"], maximumNetWeightGrams: 4000 },
  { id: "bag", kind: "CONTAINER", occupiedBayIds: ["AFT:41"], maximumNetWeightGrams: 1000 },
  { id: "cargo", kind: "CONTAINER", occupiedBayIds: ["AFT:42"], maximumNetWeightGrams: 1500 },
  { id: "overlap", kind: "CONTAINER", occupiedBayIds: ["FWD:12"], maximumNetWeightGrams: 1500 },
] };
const result: CargoCapacityResult = { mode: "CARGO_CAPACITY", aircraftType: "359", inputRevision: problem.inputRevision, status: "OPTIMAL", engine: "OR-TOOLS CP-SAT", provedObjectives: ["PALLETS", "CONTAINERS", "NET_WEIGHT"], solveMilliseconds: 1, arrangement: { palletPositionIds: ["pallet"], containerPositionIds: ["cargo"], baggagePositionIds: ["bag"], cargoNetWeightGrams: 5500 } };

test("capacity witnesses preserve baggage, resource exclusivity and exact net totals", () => {
  assert.equal(validateCargoCapacityResult(problem, result), result);
  for (const a of [
    { ...result.arrangement!, baggagePositionIds: [] },
    { ...result.arrangement!, containerPositionIds: ["overlap"] },
    { ...result.arrangement!, containerPositionIds: ["bag"] },
    { ...result.arrangement!, palletPositionIds: ["cargo"] },
    { ...result.arrangement!, cargoNetWeightGrams: 5501 },
  ]) assert.throws(() => validateCargoCapacityResult(problem, { ...result, arrangement: a }));
});
test("stale, malformed and unproved maximum claims are rejected", () => {
  assert.throws(() => validateCargoCapacityResult(problem, { ...result, inputRevision: "old" }));
  assert.throws(() => validateCargoCapacityResult(problem, { ...result, provedObjectives: ["PALLETS"] }));
  assert.throws(() => validateCargoCapacityResult(problem, { ...result, status: "UNKNOWN" }));
  assert.doesNotThrow(() => validateCargoCapacityResult(problem, { ...result, status: "FEASIBLE", provedObjectives: ["PALLETS"] }));
  assert.doesNotThrow(() => validateCargoCapacityResult(problem, { ...result, status: "UNKNOWN", provedObjectives: [], arrangement: null }));
  for (const change of [{ aircraftType: "763" }, { baggageUldCount: -1 }, { timeLimitSeconds: Infinity }, { positions: [problem.positions[0], problem.positions[0]] }]) assert.throws(() => validateCargoCapacityProblem({ ...problem, ...change }));
});
test("worker transport validates output and fails explicitly when unavailable or malformed", async () => {
  const dir = mkdtempSync(join(tmpdir(), "wab-capacity-"));
  try {
    const script = join(dir, "worker.cjs");
    writeFileSync(script, `process.stdin.resume();process.stdin.on('end',()=>process.stdout.write(${JSON.stringify(JSON.stringify(result))}));`);
    const solver = createCpSatCargoCapacitySolver({ python: process.execPath, script });
    assert.deepEqual(await solver.solve(problem), result);
    writeFileSync(script, `process.stdin.resume();process.stdin.on('end',()=>process.stdout.write('not json'));`);
    await assert.rejects(solver.solve(problem), /unreadable/);
    await assert.rejects(createCpSatCargoCapacitySolver({ python: join(dir, "missing") }).solve(problem), /could not start/);
    writeFileSync(script, `process.stdin.resume();process.stdin.on('end',()=>process.stdout.write(${JSON.stringify(JSON.stringify({ ...result, inputRevision: "old" }))}));`);
    await assert.rejects(solver.solve(problem), /Invalid cargo-capacity/);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
test("capacity worker admission and execution limits are enforced", async () => {
  const dir = mkdtempSync(join(tmpdir(), "wab-capacity-limits-"));
  try {
    const script = join(dir, "worker.cjs");
    writeFileSync(script, `process.stdin.resume();process.stdin.on('end',()=>setTimeout(()=>process.stdout.write(${JSON.stringify(JSON.stringify(result))}),250));`);
    const solver = createCpSatCargoCapacitySolver({ python: process.execPath, script });
    const first = solver.solve(problem), second = solver.solve(problem);
    await assert.rejects(solver.solve(problem), /busy/);
    await Promise.all([first, second]);
    writeFileSync(script, `process.stdin.resume();setTimeout(()=>{},10000);`);
    await assert.rejects(solver.solve({ ...problem, timeLimitSeconds: 0.01 }), /execution limit/);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
