import "server-only";
import { createHash, timingSafeEqual } from "node:crypto";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { performance } from "node:perf_hooks";
import { CapacityTestDeadlineError, createStagingCapacityWorker, type CapacityTestRunner } from "@/infrastructure/capacity/staging-worker";
import { validateCargoCapacityProblem, validateCargoCapacityResult } from "@/domain/cargo-capacity";

const headers = { "Cache-Control": "private, no-store", "X-Content-Type-Options": "nosniff" };
const digest = (v: string) => createHash("sha256").update(v).digest();
const hash = (v: string) => digest(v).toString("hex");
const caseIds = new Set(["case-01", "case-02", "case-03", "case-04", "case-05", "case-06", "case-07-infeasible"]);
async function boundedJson(stream: ReadableStream<Uint8Array> | null, limit: number) {
  if (!stream) throw Error("Missing body");
  const reader = stream.getReader(), chunks: Uint8Array[] = []; let length = 0;
  try { for (;;) { const { value, done } = await reader.read(); if (done) break; length += value.length; if (length > limit) { await reader.cancel(); throw Error("Oversized body"); } chunks.push(value); } }
  finally { reader.releaseLock(); }
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}

/** Isolated fixed-fixture endpoint; never imported by the operational workflow. */
export function createStagingCapacityEndpoint(options: { env?: Readonly<Record<string, string | undefined>>; run?: CapacityTestRunner; root?: string } = {}) {
  const env = options.env ?? process.env, run = options.run ?? createStagingCapacityWorker({ env });
  let active = 0;
  const reply = (body: unknown, status = 200) => Response.json(body, { status, headers });
  return async (request: Request): Promise<Response> => {
    const started = performance.now();
    if (env.WAB_DEPLOYMENT_ENV !== "staging" || env.WAB_CAPACITY_TESTS_ENABLED !== "true") return reply({ error: "Not found." }, 404);
    const secret = env.WAB_CAPACITY_TEST_TOKEN ?? "", auth = request.headers.get("authorization") ?? "";
    if (secret.length < 32) return reply({ error: "Staging capacity test is not configured." }, 503);
    if (auth.length > 512 || !timingSafeEqual(digest(auth), digest(`Bearer ${secret}`))) return reply({ error: "Authentication required." }, 401);
    if (request.method !== "POST") return reply({ error: "POST required." }, 405);
    if (!request.headers.get("content-type")?.startsWith("application/json")) return reply({ error: "JSON required." }, 415);
    if (active >= 1) return reply({ error: "Capacity test is busy. Retry serially." }, 429);
    let body: { caseId?: string; engine?: string; profileCase3?: boolean; totalBudgetMilliseconds?: number };
    try { body = await boundedJson(request.body, 1024); }
    catch { return reply({ error: "Invalid or oversized request." }, 400); }
    if (!body || !caseIds.has(body.caseId ?? "") || !["DATABASE", "SOLVER"].includes(body.engine ?? "") || Object.keys(body).some(k => !["caseId", "engine", "profileCase3", "totalBudgetMilliseconds"].includes(k))) return reply({ error: "Select one of the seven A350 test cases and an engine." }, 400);
    if ("profileCase3" in body && (body.profileCase3 !== true || body.caseId !== "case-03" || body.engine !== "SOLVER")) return reply({ error: "Profiling is restricted to the Case 3 solver." }, 400);
    if ("totalBudgetMilliseconds" in body && (body.totalBudgetMilliseconds !== 6000 || body.engine !== "SOLVER")) return reply({ error: "Only the six-second SOLVER test is supported." }, 400);
    // Recheck after reading the body: two concurrent uploads must not pass admission.
    if (active >= 1) return reply({ error: "Capacity test is busy. Retry serially." }, 429);
    active++;
    try {
      const inputStarted = performance.now();
      const root = options.root ?? join(process.cwd(), "solver/verification/a350-v2-seven-scenarios-2026-10-23/final");
      const registry = JSON.parse(await readFile(join(root, "results.json"), "utf8"));
      const expected = registry.rows.find((r: { id: string }) => r.id === body.caseId);
      const raw = await readFile(join(root, "inputs", `${body.caseId}.json`), "utf8");
      if (!expected || expected.outcome !== "EQUIVALENT" || hash(raw) !== expected.inputSha256) throw Error("Fixture integrity failure");
      const problem = validateCargoCapacityProblem(JSON.parse(raw));
      const inputMilliseconds = performance.now() - inputStarted;
      const executionStarted = performance.now();
      const measured = await run({ caseId: body.caseId!, engine: body.engine as "DATABASE" | "SOLVER", inputSha256: hash(raw), problem, ...(body.profileCase3 ? { profileCase3: true as const } : {}), ...(body.totalBudgetMilliseconds ? { totalBudgetMilliseconds: 6000 as const, deadlineMilliseconds: started + 5500 } : {}) });
      const executionRoundTripMilliseconds = performance.now() - executionStarted;
      const validationStarted = performance.now();
      if (measured.engine !== body.engine || measured.inputSha256 !== hash(raw) || !Number.isFinite(measured.calculationMilliseconds) || measured.calculationMilliseconds < 0 || measured.calculationMilliseconds > 65000) throw Error("Invalid worker response");
      if (!measured.result || typeof measured.result !== "object") throw Error("Invalid worker result");
      // The witness validator uses the solver envelope; preserve the actual engine
      // in the response while validating the database arrangement identically.
      const result = validateCargoCapacityResult(problem, { ...measured.result, engine: "OR-TOOLS CP-SAT", solveMilliseconds: 0 });
      const proven = ["OPTIMAL", "INFEASIBLE"].includes(result.status);
      const matches = proven && result.status === expected.solver.result.status && (result.arrangement?.cargoNetWeightGrams ?? null) === (expected.solver.result.arrangement?.cargoNetWeightGrams ?? null);
      return reply({ caseId: body.caseId, engine: body.engine, inputSha256: hash(raw), inputRevision: problem.inputRevision, result: measured.result, outcome: proven ? matches ? "VERIFIED" : "MISMATCH" : "INCONCLUSIVE", validation: "PASS",
        timings: { calculationMilliseconds: measured.calculationMilliseconds, workerStartupMilliseconds: measured.workerStartupMilliseconds ?? null, executionRoundTripMilliseconds, inputMilliseconds, validationMilliseconds: performance.now() - validationStarted, handlerMilliseconds: performance.now() - started }, backend: measured.deployment ?? null, ...(body.totalBudgetMilliseconds ? { publication: { testingOnly: true, state: proven ? matches ? result.status === "INFEASIBLE" ? "PROVEN_INFEASIBLE" : "PROVEN_MAXIMUM" : "MISMATCH" : result.arrangement ? "VALID_UNPROVEN" : "NO_VALID_RESULT", targetTotalMilliseconds: 6000, serverBudgetMilliseconds: 5500, message: proven ? "Calculation completed." : result.arrangement ? "Valid arrangement; maximum not confirmed." : "No valid arrangement available within the time budget." }, executionBudget: measured.executionBudget ?? null } : {}), ...(body.profileCase3 ? { searchProfile: measured.searchProfile ?? null } : {}) });
    } catch (error) {
      if (body.totalBudgetMilliseconds && error instanceof CapacityTestDeadlineError) return reply({ caseId: body.caseId, engine: body.engine, outcome: "INCOMPLETE", result: null, publication: { testingOnly: true, state: "NO_VALID_RESULT", targetTotalMilliseconds: 6000, message: "No validated arrangement available within the total time budget." }, timings: { handlerMilliseconds: performance.now() - started } });
      return reply({ error: "Unable to complete the staging capacity test; no maximum is confirmed." }, 503);
    }
    finally { active--; }
  };
}
