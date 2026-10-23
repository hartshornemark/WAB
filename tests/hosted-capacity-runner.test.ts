import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

test("hosted caller preserves non-JSON HTTP failure status without losing or duplicating samples", () => {
  const root = mkdtempSync(join(tmpdir(), "hosted-capacity-"));
  try {
    const stub = "data:text/javascript," + encodeURIComponent("globalThis.fetch=async()=>new Response('upstream unavailable',{status:503});");
    const result = spawnSync(process.execPath, ["--import", stub, "solver/run_hosted_capacity_measurements.mjs", "--run", "--smoke", "--cases", "case-07-infeasible", "--url", "https://staging.invalid", "--output", join(root, "results")], { env: { ...process.env, WAB_CAPACITY_TEST_TOKEN: "test-only-token-012345678901234567890123456789" }, encoding: "utf8" });
    assert.equal(result.status, 0, result.stderr);
    const report = JSON.parse(readFileSync(join(root, "results/results.json"), "utf8"));
    assert.equal(report.rows.length, 2);
    for (const row of report.rows) { assert.equal(row.outcome, "ERROR"); assert.equal(row.httpStatus, 503); assert.equal(row.error, "Non-JSON HTTP response"); }
  } finally { rmSync(root, { recursive: true, force: true }); }
});
