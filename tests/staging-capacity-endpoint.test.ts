import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createStagingCapacityEndpoint } from "../src/infrastructure/capacity/staging-endpoint";
const env = { WAB_DEPLOYMENT_ENV: "staging", WAB_CAPACITY_TESTS_ENABLED: "true", WAB_CAPACITY_TEST_TOKEN: "test-only-operator-token-01234567890123456789", WAB_CAPACITY_SERVICE_TOKEN: "test-only-backend-token-01234567890123456789", WAB_CAPACITY_SERVICE_URL: "http://a350-capacity:8080" };
const request = (body: unknown = { caseId: "case-01", engine: "DATABASE" }, token = env.WAB_CAPACITY_TEST_TOKEN) => new Request("https://staging.example/api/internal/a350-capacity", { method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` }, body: JSON.stringify(body) });
const saved = JSON.parse(readFileSync("solver/verification/a350-v2-seven-scenarios-2026-10-23/final/case-01.json", "utf8"));
const measured = () => ({ engine: "DATABASE", inputSha256: saved.inputSha256, result: saved.database.result, calculationMilliseconds: 12 });

test("staging route fails closed outside explicit staging and authenticates before loading fixtures", async () => {
  const never = (async () => { throw Error("must not call"); }) as typeof fetch;
  assert.equal((await createStagingCapacityEndpoint({ env: {}, fetch: never })(request())).status, 404);
  assert.equal((await createStagingCapacityEndpoint({ env: { ...env, WAB_DEPLOYMENT_ENV: "production" }, fetch: never })(request())).status, 404);
  assert.equal((await createStagingCapacityEndpoint({ env, fetch: never })(request(undefined, "wrong"))).status, 401);
  assert.equal((await createStagingCapacityEndpoint({ env: { ...env, WAB_CAPACITY_TEST_TOKEN: "short" }, fetch: never })(request())).status, 503);
});

test("fixed-case request cannot supply positions, another aircraft, or arbitrary configuration", async () => {
  const endpoint = createStagingCapacityEndpoint({ env });
  for (const body of [{ caseId: "case-76", engine: "DATABASE" }, { caseId: "case-01", engine: "AUTOLOAD" }, { caseId: "case-01", engine: "SOLVER", problem: {} }, { padding: "X".repeat(2000) }]) assert.equal((await endpoint(request(body))).status, 400);
});

test("hosted result is independently validated, compared with the sealed offer, and never cached", async () => {
  let called = false;
  const fake = (async (url: URL, init: RequestInit) => {
    assert.equal(url.toString(), "http://a350-capacity:8080/v1/capacity");
    assert.equal(init.redirect, "error"); assert.equal(init.cache, "no-store");
    const headers = init.headers as Record<string, string>;
    assert.equal(headers.Authorization, `Bearer ${env.WAB_CAPACITY_SERVICE_TOKEN}`);
    assert(!headers.Authorization.includes(env.WAB_CAPACITY_TEST_TOKEN));
    const input = JSON.parse(init.body as string); assert.equal(input.inputSha256, saved.inputSha256);
    called = true; return Response.json(measured());
  }) as typeof fetch;
  const response = await createStagingCapacityEndpoint({ env, fetch: fake })(request());
  assert.equal(response.status, 200); assert(called); assert.match(response.headers.get("cache-control")!, /no-store/);
  const body = await response.json(); assert.equal(body.outcome, "VERIFIED"); assert.equal(body.validation, "PASS");
  assert.equal(body.timings.calculationMilliseconds, 12);
});

test("stale, wrong-engine and invalid witnesses fail, while unproved maxima stay inconclusive", async () => {
  for (const bad of [{ ...measured(), inputSha256: "stale" }, { ...measured(), engine: "SOLVER" }, { ...measured(), result: { ...saved.database.result, inputRevision: "stale" } }]) {
    const response = await createStagingCapacityEndpoint({ env, fetch: (async () => Response.json(bad)) as typeof fetch })(request()); assert.equal(response.status, 503);
  }
  const feasible = { ...measured(), result: { ...saved.database.result, status: "FEASIBLE" } };
  const response = await createStagingCapacityEndpoint({ env, fetch: (async () => Response.json(feasible)) as typeof fetch })(request());
  assert.equal((await response.json()).outcome, "INCONCLUSIVE");
});

test("only one test request per app process is admitted and invalid backend URLs never receive secrets", async () => {
  let release!: () => void;
  const blocked = new Promise<void>(r => { release = r; });
  let started!: () => void;
  const entered = new Promise<void>(r => { started = r; });
  const endpoint = createStagingCapacityEndpoint({ env, fetch: (async () => { started(); await blocked; return Response.json(measured()); }) as typeof fetch });
  const first = endpoint(request()); await entered;
  assert.equal((await endpoint(request())).status, 429); release(); assert.equal((await first).status, 200);
  let called = false;
  const invalid = createStagingCapacityEndpoint({ env: { ...env, WAB_CAPACITY_SERVICE_URL: "http://untrusted.example" }, fetch: (async () => { called = true; return Response.json(measured()); }) as typeof fetch });
  assert.equal((await invalid(request())).status, 503); assert.equal(called, false);
});
