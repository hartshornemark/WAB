import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { validateCargoCapacityProblem, validateCargoCapacityResult } from "../src/domain/cargo-capacity";

const root = "solver/verification/a350-v2-seven-scenarios-2026-10-23";
const frozen = "tests/fixtures/cargo-capacity/passenger-scenarios-v2";
const json = (path: string) => JSON.parse(readFileSync(path, "utf8"));
const sha = (data: string | Buffer) => createHash("sha256").update(data).digest("hex");

test("sealed seven-case evidence has identical reservations, validated witnesses and proven equivalent outcomes", () => {
  const report = json(root + "/final/results.json"), manifest = json(frozen + "/manifest.json");
  assert.equal(report.manifestSha256, sha(readFileSync(frozen + "/manifest.json")));
  assert.equal(report.rows.length, 7);
  assert(report.finishedAt);
  for (const c of manifest.cases) {
    const row = report.rows.find((r: { id: string }) => r.id === c.id);
    const original = json(frozen + "/" + c.solverInput), raw = readFileSync(root + "/final/inputs/" + c.id + ".json", "utf8");
    const p = validateCargoCapacityProblem(JSON.parse(raw));
    assert.equal(row.originalInputSha256, c.inputSha256);
    assert.equal(row.inputSha256, sha(raw));
    assert.equal(row.inputRevision, p.inputRevision);
    assert.deepEqual(p, { ...original, timeLimitSeconds: 10, inputRevision: p.inputRevision });
    assert.equal(row.baggageReservationHash, sha(JSON.stringify(original.baggageUlds)));
    assert.equal(row.fixedReservationHash, sha(JSON.stringify(original.fixedLoads)));
    for (const engine of [row.database, row.solver]) {
      assert.equal(engine.validation, "PASS");
      validateCargoCapacityResult(p, { ...engine.result, engine: "OR-TOOLS CP-SAT", solveMilliseconds: engine.result.solveMilliseconds ?? 0 });
    }
    assert.equal(row.outcome, "EQUIVALENT");
    assert.equal(row.database.result.status, row.solver.result.status);
    assert.equal(row.database.result.arrangement?.cargoNetWeightGrams ?? null, row.solver.result.arrangement?.cargoNetWeightGrams ?? null);
    if (c.id === "case-07-infeasible") {
      assert.equal(row.database.result.status, "INFEASIBLE");
      assert(p.baggageUlds.length > p.positions.filter(pos => pos.kind === "CONTAINER").length);
    } else assert.equal(row.database.result.status, "OPTIMAL");
  }
  for (const [path, hash] of Object.entries(report.codeSha256)) assert.equal(sha(readFileSync(root + "/code/" + path)), hash);
});

test("initial timeout and unproved outcomes remain inconclusive in the preserved evidence", () => {
  const initial = json(root + "/initial/results.json");
  assert.equal(initial.rows.filter((r: { outcome: string }) => r.outcome === "INCONCLUSIVE").length, 4);
  assert.equal(initial.rows.find((r: { id: string }) => r.id === "case-03").solver.result.status, "FEASIBLE");
});
