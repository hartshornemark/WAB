import test from "node:test";
import assert from "node:assert/strict";
// @ts-expect-error Measurement helpers are plain JavaScript outside the application build.
import { distribution, summariseMeasurement } from "../solver/cargo_capacity_statistics.mjs";

test("timing medians and nearest-rank percentiles use the full recorded sample", () => {
  assert.deepEqual(distribution([4, 1, 3, 2]), { samples: 4, minimum: 1, median: 2.5, p95: 4, maximum: 4 });
  assert.equal(distribution(Array.from({ length: 20 }, (_, i) => i + 1)).p95, 19);
  assert.equal(distribution([]).median, null);
  assert.equal(distribution([0]).median, 0);
  assert.throws(() => distribution([NaN]));
  assert.throws(() => distribution([-1]));
});

test("warmups, failed/unproved samples and restarted warm sessions cannot produce a successful latency claim", () => {
  const base = { caseId: "CASE", engine: "solver", phase: "warm", sessionReused: true, calculationMilliseconds: 2, completeRequestMilliseconds: 5 };
  const report = { scope: "synthetic", repetitions: { warmPerCase: 4, coldPerCase: 2 }, rows: [
    { ...base, phase: "warmup", outcome: "VERIFIED", calculationMilliseconds: 100 },
    { ...base, outcome: "VERIFIED" },
    { ...base, outcome: "ERROR", calculationMilliseconds: 200 },
    { ...base, outcome: "INCONCLUSIVE", result: { status: "FEASIBLE" }, calculationMilliseconds: 300 },
    { ...base, outcome: "VERIFIED", sessionReused: false, calculationMilliseconds: 1 },
  ] };
  const result = summariseMeasurement(report), warm = result.summary.find((r: { engine: string; phase: string }) => r.engine === "solver" && r.phase === "warm");
  assert.equal(warm.requested, 4); assert.equal(warm.verified, 1);
  assert.equal(warm.errors, 1); assert.equal(warm.inconclusive, 1);
  assert.equal(warm.warmSessionRestartsExcluded, 1);
  assert.equal(warm.metrics.calculationMilliseconds.median, 2);
  assert.equal(warm.metrics.workerStartupMilliseconds.samples, 0);
  assert.equal(result.failures.length, 2); assert.equal(result.warmupsExcluded, 1);
});
