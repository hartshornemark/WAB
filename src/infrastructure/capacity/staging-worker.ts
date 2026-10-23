import "server-only";
import { spawn } from "node:child_process";
import { join } from "node:path";
import { performance } from "node:perf_hooks";
import type { CargoCapacityProblem } from "@/domain/cargo-capacity";

export type CapacityTestJob = { caseId: string; engine: "DATABASE" | "SOLVER"; inputSha256: string; problem: CargoCapacityProblem };
export type CapacityTestMeasurement = {
  engine: string; inputSha256: string; result: unknown; calculationMilliseconds: number;
  workerStartupMilliseconds?: number; deployment?: unknown;
};
export type CapacityTestRunner = (job: CapacityTestJob) => Promise<CapacityTestMeasurement>;

export function createStagingCapacityWorker(options: { env?: Readonly<Record<string, string | undefined>>; root?: string } = {}): CapacityTestRunner {
  const env = options.env ?? process.env, root = options.root ?? process.cwd();
  return async job => {
    const childEnv: NodeJS.ProcessEnv = { NODE_ENV: "production", PATH: env.PATH ?? "", PYTHONUNBUFFERED: "1", CAPACITY_RELEASE_ID: env.CAPACITY_RELEASE_ID ?? "unlabelled" };
    if (job.engine === "DATABASE") {
      if (!env.CAPACITY_DATABASE_URL) throw Error("Benchmark database is not configured");
      childEnv.CAPACITY_DATABASE_URL = env.CAPACITY_DATABASE_URL;
      if (env.CAPACITY_DATABASE_CA_FILE) childEnv.CAPACITY_DATABASE_CA_FILE = env.CAPACITY_DATABASE_CA_FILE;
    }
    const raw = JSON.stringify(job);
    if (Buffer.byteLength(raw) > 256_000) throw Error("Oversized benchmark job");
    return new Promise((resolve, reject) => {
      const started = performance.now();
      const child = spawn(/*turbopackIgnore: true*/ env.WAB_SOLVER_PYTHON ?? "python3", [join(root, "solver/staging/app_worker.py")], { env: childEnv, stdio: ["pipe", "pipe", "pipe"] });
      const output: Buffer[] = []; let stdoutBytes = 0, stderrBytes = 0, settled = false, readyAt: number | undefined;
      let pending = "";
      const finish = (error?: Error) => {
        if (settled) return;
        settled = true; clearTimeout(timer);
        if (error) { child.kill("SIGKILL"); reject(error); return; }
        try {
          const lines = Buffer.concat(output).toString("utf8").trim().split("\n");
          if (lines.length !== 2 || JSON.parse(lines[0]).ready !== true || readyAt === undefined) throw Error("Invalid worker protocol");
          resolve({ ...JSON.parse(lines[1]), workerStartupMilliseconds: readyAt - started });
        } catch { reject(Error("Invalid benchmark worker output")); }
      };
      // Give imports a separate bounded startup budget. The model's sealed
      // search budget starts after readiness, not when the OS process launches.
      let timer = setTimeout(() => finish(Error("Benchmark startup execution limit; no maximum confirmed")), job.engine === "SOLVER" ? 15_000 : 68_000);
      child.stdout.on("data", (chunk: Buffer) => {
        stdoutBytes += chunk.length;
        if (stdoutBytes > 1_000_000) { finish(Error("Benchmark output limit")); return; }
        output.push(chunk);
        if (readyAt === undefined) {
          pending += chunk.toString("utf8");
          if (pending.includes("\n")) {
            try {
              if (JSON.parse(pending.split("\n")[0]).ready === true) {
                readyAt = performance.now();
                if (job.engine === "SOLVER") {
                  clearTimeout(timer);
                  timer = setTimeout(() => finish(Error("Benchmark calculation execution limit; no maximum confirmed")), (job.problem.timeLimitSeconds + 2) * 1000);
                }
              }
            }
            catch { finish(Error("Invalid benchmark worker readiness")); }
          }
        }
      });
      child.stderr.on("data", (chunk: Buffer) => { stderrBytes += chunk.length; if (stderrBytes > 1_000_000) finish(Error("Benchmark error-output limit")); });
      child.on("error", () => finish(Error("Benchmark worker could not start")));
      child.stdin.on("error", () => finish(Error("Benchmark input failed")));
      child.on("close", code => finish(code === 0 ? undefined : Error("Benchmark worker failed; no maximum confirmed")));
      child.stdin.end(raw);
    });
  };
}
