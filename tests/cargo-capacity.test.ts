import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, rmSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { PGlite } from "@electric-sql/pglite";
import cases from "./fixtures/cargo-capacity/rule-unit-cases-v2.json";
import { validateCargoCapacityProblem, validateCargoCapacityResult, type CargoCapacityProblem, type CargoCapacityResult } from "../src/domain/cargo-capacity";
import { createCpSatCargoCapacitySolver } from "../src/infrastructure/solver/cp-sat-cargo-capacity-solver";

const problem = cases.cases[0].input as CargoCapacityProblem;
const result: CargoCapacityResult = { mode: "CARGO_CAPACITY", aircraftType: "359", rulesVersion: "A350_MAX_NET_CARGO_V2", inputRevision: problem.inputRevision, status: "OPTIMAL", engine: "OR-TOOLS CP-SAT", solveMilliseconds: 1, arrangement: { cargoUlds: [{ positionId: "C1", netWeightGrams: 2400 }, { positionId: "C2", netWeightGrams: 2400 }], baggageUlds: [], bulkCargo: [], cargoNetWeightGrams: 4800, cargoTareWeightGrams: 200, cargoGrossWeightGrams: 5000 } };

test("offline database reference follows the agreed small rule-unit examples", async t => {
  const db = new PGlite();
  try {
    await db.exec(readFileSync("solver/reference/max_net_cargo_v2.sql", "utf8"));
    await db.exec(readFileSync("solver/reference/frontier_net_cargo_v2.sql", "utf8"));
    for (const c of cases.cases) await t.test(c.name, async () => {
      const p = validateCargoCapacityProblem(c.input);
      const r = (await db.query<{ result: CargoCapacityResult }>("select capacity_reference.max_net_cargo_v2($1::jsonb) result", [JSON.stringify(p)])).rows[0].result;
      assert.equal(r.status, c.expectedStatus);
      assert.equal(r.arrangement?.cargoNetWeightGrams ?? null, c.expectedNetGrams);
      // SQL reference has no timing or engine assertion; the independent
      // validator still checks its complete witness against all same limits.
      validateCargoCapacityResult(p, { ...r, engine: "OR-TOOLS CP-SAT", solveMilliseconds: 0 });
    });
  } finally { await db.close(); }
});

test("independent validator rejects overlap, tare, stale rules and payload violations", () => {
  assert.equal(validateCargoCapacityResult(problem, result), result);
  assert.throws(() => validateCargoCapacityResult(problem, { ...result, inputRevision: "old" }));
  assert.throws(() => validateCargoCapacityResult(problem, { ...result, rulesVersion: "A350_PALLET_FIRST_DB_V1" }));
  assert.throws(() => validateCargoCapacityResult(problem, { ...result, arrangement: { ...result.arrangement, cargoTareWeightGrams: 0 } }));
  assert.throws(() => validateCargoCapacityResult(problem, { ...result, arrangement: { ...result.arrangement, cargoUlds: [...result.arrangement!.cargoUlds, { positionId: "P", netWeightGrams: 1 }] } }));
  assert.throws(() => validateCargoCapacityResult({ ...problem, maximumZeroFuelWeightGrams: 6000 }, result));
  assert.throws(() => validateCargoCapacityProblem({ ...problem, rulesVersion: undefined }));
  assert.doesNotThrow(() => validateCargoCapacityResult(problem, { ...result, status: "FEASIBLE" }));
});

test("capacity worker validates output and rejects unavailable, malformed and timed-out execution", async () => {
  const dir = mkdtempSync(join(tmpdir(), "wab-capacity-"));
  try {
    const script = join(dir, "worker.cjs");
    writeFileSync(script, `process.stdin.resume();process.stdin.on('end',()=>process.stdout.write(${JSON.stringify(JSON.stringify(result))}));`);
    const solver = createCpSatCargoCapacitySolver({ python: process.execPath, script });
    assert.deepEqual(await solver.solve(problem), result);
    writeFileSync(script, `process.stdin.resume();process.stdin.on('end',()=>process.stdout.write('not json'));`);
    await assert.rejects(solver.solve(problem), /unreadable/);
    await assert.rejects(createCpSatCargoCapacitySolver({ python: join(dir, "missing") }).solve(problem), /could not start/);
    writeFileSync(script, `process.stdin.resume();setTimeout(()=>{},10000);`);
    await assert.rejects(solver.solve({ ...problem, timeLimitSeconds: 0.01 }), /execution limit/);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
