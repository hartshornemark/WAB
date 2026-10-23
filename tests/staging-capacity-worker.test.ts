import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createStagingCapacityWorker, type CapacityTestJob } from "../src/infrastructure/capacity/staging-worker";
const row = JSON.parse(readFileSync("solver/verification/a350-v2-seven-scenarios-2026-10-23/final/case-07-infeasible.json", "utf8"));
const job: CapacityTestJob = { engine: "SOLVER", caseId: "case-07-infeasible", inputSha256: row.inputSha256, problem: JSON.parse(readFileSync("solver/verification/a350-v2-seven-scenarios-2026-10-23/final/inputs/case-07-infeasible.json", "utf8")) };
function fakeWorker(code: string) {
  const root = mkdtempSync(join(tmpdir(), "capacity-worker-")); mkdirSync(join(root, "solver/staging"), { recursive: true });
  writeFileSync(join(root, "solver/staging/app_worker.py"), code);
  return { root, close: () => rmSync(root, { recursive: true, force: true }) };
}

test("local child receives engine-specific credentials only and records actual startup", async () => {
  const worker = fakeWorker(`process.stdin.resume();process.stdin.on('end',()=>{console.log(JSON.stringify({ready:true}));console.log(JSON.stringify({engine:'SOLVER',inputSha256:'test',result:process.env,calculationMilliseconds:0}));});`);
  try {
    const env = { WAB_SOLVER_PYTHON: process.execPath, PATH: process.env.PATH, CAPACITY_RELEASE_ID: "reviewed", CAPACITY_DATABASE_URL: "database-secret", CAPACITY_DATABASE_CA_FILE: "/ca", WAB_CAPACITY_TEST_TOKEN: "operator-secret", SUPABASE_SERVICE_ROLE_KEY: "unrelated-secret" };
    const run = createStagingCapacityWorker({ env, root: worker.root });
    const solver = await run(job), solverEnv = solver.result as Record<string, string>;
    assert.equal(solverEnv.CAPACITY_DATABASE_URL, undefined); assert.equal(solverEnv.CAPACITY_DATABASE_CA_FILE, undefined);
    assert.equal(solverEnv.WAB_CAPACITY_TEST_TOKEN, undefined); assert.equal(solverEnv.SUPABASE_SERVICE_ROLE_KEY, undefined);
    assert.equal(solverEnv.CAPACITY_RELEASE_ID, "reviewed"); assert(solver.workerStartupMilliseconds! >= 0);
    const database = await run({ ...job, engine: "DATABASE" }), databaseEnv = database.result as Record<string, string>;
    assert.equal(databaseEnv.CAPACITY_DATABASE_URL, "database-secret"); assert.equal(databaseEnv.CAPACITY_DATABASE_CA_FILE, "/ca");
    assert.equal(databaseEnv.WAB_CAPACITY_TEST_TOKEN, undefined); assert.equal(databaseEnv.SUPABASE_SERVICE_ROLE_KEY, undefined);
    await assert.rejects(createStagingCapacityWorker({ env: { WAB_SOLVER_PYTHON: process.execPath }, root: worker.root })({ ...job, engine: "DATABASE" }), /not configured/);
  } finally { worker.close(); }
});

test("local worker rejects broken protocol, failed execution and unbounded output without exposing errors", async () => {
  for (const code of ["process.stdout.write('invalid');", "console.error('secret password');process.exit(1);", "process.stdout.write('x'.repeat(1_100_000));"]) {
    const worker = fakeWorker(code);
    try { await assert.rejects(createStagingCapacityWorker({ env: { WAB_SOLVER_PYTHON: process.execPath }, root: worker.root })(job), e => e instanceof Error && !e.message.includes("password")); }
    finally { worker.close(); }
  }
});

test("real packaged worker dispatches the sealed infeasible solver case", { skip: !process.env.WAB_TEST_PYTHON }, async () => {
  const run = createStagingCapacityWorker({ env: { WAB_SOLVER_PYTHON: process.env.WAB_TEST_PYTHON, PATH: process.env.PATH } });
  const result = await run(job);
  assert.equal((result.result as { status: string }).status, "INFEASIBLE");
  assert.equal(result.inputSha256, job.inputSha256); assert.equal(result.engine, "SOLVER");
});
