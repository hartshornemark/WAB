import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { validateCargoCapacityProblem, validateCargoCapacityResult } from "../src/domain/cargo-capacity";

const root = "solver/benchmarks/a350-v2-local-request-2026-10-23";
const json = (p: string) => JSON.parse(readFileSync(p, "utf8"));
const sha = (v: string | Buffer) => createHash("sha256").update(v).digest("hex");

test("repeated measurement evidence includes every requested sample and keeps core/request boundaries separate", () => {
  const report = json(root + "/results.json"), summary = json(root + "/summary.json");
  const expected = json("solver/verification/a350-v2-seven-scenarios-2026-10-23/final/results.json");
  assert(report.finishedAt); assert.equal(report.rows.length, 196);
  assert.equal(summary.measuredRequests, 182); assert.equal(summary.warmupsExcluded, 14);
  assert.equal(summary.completeWithoutFailures, true); assert.equal(summary.failures.length, 0);
  for (const c of expected.rows) {
    const raw = readFileSync(root + "/inputs/" + c.id + ".json", "utf8");
    assert.equal(sha(raw), c.inputSha256);
    const p = validateCargoCapacityProblem(JSON.parse(raw));
    for (const engine of ["database", "solver"]) for (const phase of ["cold", "warmup", "warm"]) {
      const rows = report.rows.filter((r: { caseId: string; engine: string; phase: string }) => r.caseId === c.id && r.engine === engine && r.phase === phase);
      assert.equal(rows.length, phase === "cold" ? 3 : phase === "warm" ? 10 : 1);
      for (const r of rows) {
        assert.equal(r.outcome, "VERIFIED"); assert.equal(r.inputSha256, c.inputSha256);
        assert.equal(r.sessionReused, phase === "warm");
        for (const key of ["calculationMilliseconds", "completeRequestMilliseconds", "backendMilliseconds", "serverHandlerMilliseconds", "inputMilliseconds", "validationMilliseconds"]) assert(typeof r[key] === "number" && Number.isFinite(r[key]) && r[key] >= 0);
        assert(r.calculationMilliseconds <= r.backendMilliseconds + 2); // SQL wall clock has 1 ms resolution.
        assert(r.backendMilliseconds <= r.serverHandlerMilliseconds);
        assert(r.serverHandlerMilliseconds <= r.completeRequestMilliseconds);
        if (engine === "solver") {
          assert(r.workerStartupMilliseconds > 0);
          assert(r.workerRoundTripMilliseconds >= r.workerStartupMilliseconds);
          assert(r.workerRoundTripMilliseconds <= r.backendMilliseconds);
        }
        validateCargoCapacityResult(p, { ...r.result, engine: "OR-TOOLS CP-SAT", solveMilliseconds: r.result.solveMilliseconds ?? 0 });
        assert.equal(r.result.status, c.solver.result.status);
        assert.equal(r.result.arrangement?.cargoNetWeightGrams ?? null, c.solver.result.arrangement?.cargoNetWeightGrams ?? null);
      }
    }
  }
  for (const [file, hash] of Object.entries({ ...report.codeSha256, ...summary.analysisCodeSha256 })) assert.equal(sha(readFileSync(root + "/code/" + file)), hash);
  for (const row of summary.summary) {
    assert.equal(row.requested, row.verified);
    if (row.phase === "warm") assert.equal(row.metrics.serviceStartupMilliseconds.samples, 0);
    if (row.engine === "database") assert.equal(row.metrics.workerStartupMilliseconds.samples, 0);
  }
});
