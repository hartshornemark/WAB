import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createStagingCapacityEndpoint } from "../src/infrastructure/capacity/staging-endpoint";
import { CapacityTestDeadlineError, type CapacityTestRunner } from "../src/infrastructure/capacity/staging-worker";
const env = { WAB_DEPLOYMENT_ENV: "staging", WAB_CAPACITY_TESTS_ENABLED: "true", WAB_CAPACITY_TEST_TOKEN: "test-only-operator-token-01234567890123456789" };
const request = (body: unknown = { caseId: "case-01", engine: "DATABASE" }, token = env.WAB_CAPACITY_TEST_TOKEN) => new Request("https://staging.example/api/internal/a350-capacity", { method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` }, body: JSON.stringify(body) });
const saved = JSON.parse(readFileSync("solver/verification/a350-v2-seven-scenarios-2026-10-23/final/case-01.json", "utf8"));
const measured = () => ({ engine: "DATABASE", inputSha256: saved.inputSha256, result: saved.database.result, calculationMilliseconds: 12 });

test("staging route fails closed outside explicit staging and authenticates before loading fixtures", async () => {
  const never: CapacityTestRunner = async () => { throw Error("must not call"); };
  assert.equal((await createStagingCapacityEndpoint({ env: {}, run: never })(request())).status, 404);
  assert.equal((await createStagingCapacityEndpoint({ env: { ...env, WAB_DEPLOYMENT_ENV: "production" }, run: never })(request())).status, 404);
  assert.equal((await createStagingCapacityEndpoint({ env, run: never })(request(undefined, "wrong"))).status, 401);
  assert.equal((await createStagingCapacityEndpoint({ env: { ...env, WAB_CAPACITY_TEST_TOKEN: "short" }, run: never })(request())).status, 503);
});

test("fixed-case request rejects arbitrary positions, aircraft, configuration and oversized bodies", async () => {
  const endpoint = createStagingCapacityEndpoint({ env });
  for (const body of [null, [], { caseId: "case-76", engine: "DATABASE" }, { caseId: "case-01", engine: "AUTOLOAD" }, { caseId: "case-01", engine: "SOLVER", problem: {} }, { padding: "X".repeat(2000) }]) assert.equal((await endpoint(request(body))).status, 400);
});

test("app-local result is independently validated, compared with sealed offer and never cached", async () => {
  let called = false;
  const run: CapacityTestRunner = async job => {
    assert.equal(job.inputSha256, saved.inputSha256); assert.equal(job.engine, "DATABASE");
    assert.equal(job.problem.aircraftType, "359"); called = true; return measured();
  };
  const response = await createStagingCapacityEndpoint({ env, run })(request());
  assert.equal(response.status, 200); assert(called); assert.match(response.headers.get("cache-control")!, /no-store/);
  const body = await response.json(); assert.equal(body.outcome, "VERIFIED"); assert.equal(body.validation, "PASS");
  assert.equal(body.timings.calculationMilliseconds, 12); assert(body.timings.executionRoundTripMilliseconds >= 0);
  assert.equal(body.timings.backendRoundTripMilliseconds, undefined);
});

test("stale, wrong-engine and invalid witnesses fail while unproved maxima stay inconclusive", async () => {
  for (const bad of [{ ...measured(), inputSha256: "stale" }, { ...measured(), engine: "SOLVER" }, { ...measured(), result: { ...saved.database.result, inputRevision: "stale" } }, { ...measured(), calculationMilliseconds: -1 }]) {
    assert.equal((await createStagingCapacityEndpoint({ env, run: async () => bad })(request())).status, 503);
  }
  const feasible = { ...measured(), result: { ...saved.database.result, status: "FEASIBLE" } };
  const response = await createStagingCapacityEndpoint({ env, run: async () => feasible })(request());
  assert.equal((await response.json()).outcome, "INCONCLUSIVE");
});

test("one test per process is admitted and failures release admission without exposing secrets", async () => {
  let release!: () => void, started!: () => void;
  const blocked = new Promise<void>(r => { release = r; }), entered = new Promise<void>(r => { started = r; });
  const endpoint = createStagingCapacityEndpoint({ env, run: async () => { started(); await blocked; return measured(); } });
  const first = endpoint(request()); await entered;
  assert.equal((await endpoint(request())).status, 429); release(); assert.equal((await first).status, 200);
  let fail = true;
  const failing = createStagingCapacityEndpoint({ env, run: async () => { if (fail) throw Error("secret connection password"); return measured(); } });
  const error = await failing(request()); assert.equal(error.status, 503); assert(!JSON.stringify(await error.json()).includes("password"));
  fail = false; assert.equal((await failing(request())).status, 200);
});


test("profiling is restricted to Case 3 solver and returned only when requested", async () => {
  const endpoint = createStagingCapacityEndpoint({env, run: async job => {
    assert.equal(job.profileCase3, true);
    const row = JSON.parse(readFileSync("solver/verification/a350-v2-seven-scenarios-2026-10-23/final/case-03.json", "utf8"));
    return {engine:"SOLVER", inputSha256:row.inputSha256, result:row.solver.result, calculationMilliseconds:2, searchProfile:{version:"CASE3_INCUMBENTS_V1"}};
  }});
  for (const body of [{caseId:"case-01",engine:"SOLVER",profileCase3:true},{caseId:"case-03",engine:"DATABASE",profileCase3:true},{caseId:"case-03",engine:"SOLVER",profileCase3:false},{caseId:"case-03",engine:"SOLVER",profileCase3:1}]) assert.equal((await endpoint(request(body))).status,400);
  const response = await endpoint(request({caseId:"case-03",engine:"SOLVER",profileCase3:true}));
  assert.equal(response.status,200);
  assert.equal((await response.json()).searchProfile.version,"CASE3_INCUMBENTS_V1");
});


test("six-second publication is solver-only, validates before publishing and labels unproved results", async()=>{
  const run:CapacityTestRunner=async job=>{assert.equal(job.totalBudgetMilliseconds,6000);assert(Number.isFinite(job.deadlineMilliseconds));return {...measured(),engine:"SOLVER",result:{...saved.database.result,status:"FEASIBLE"}};};
  const endpoint=createStagingCapacityEndpoint({env,run});
  for(const body of [{caseId:"case-01",engine:"DATABASE",totalBudgetMilliseconds:6000},{caseId:"case-01",engine:"SOLVER",totalBudgetMilliseconds:5000}])assert.equal((await endpoint(request(body))).status,400);
  const response=await endpoint(request({caseId:"case-01",engine:"SOLVER",totalBudgetMilliseconds:6000}));
  const body=await response.json();assert.equal(body.publication.state,"VALID_UNPROVEN");assert.equal(body.validation,"PASS");assert.equal(body.outcome,"INCONCLUSIVE");
  const expired=createStagingCapacityEndpoint({env,run:async()=>{throw new CapacityTestDeadlineError();}});
  const incomplete=await (await expired(request({caseId:"case-01",engine:"SOLVER",totalBudgetMilliseconds:6000}))).json();
  assert.equal(incomplete.result,null);assert.equal(incomplete.publication.state,"NO_VALID_RESULT");
});
