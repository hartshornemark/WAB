import "server-only";
import { spawn } from "node:child_process";
import { join } from "node:path";
import { validateCargoCapacityProblem, validateCargoCapacityResult } from "@/domain/cargo-capacity";
import type { CargoCapacitySolver } from "@/ports/cargo-capacity-solver";

// A per-process bound. Deployment-wide admission control remains an integration task.
let running = 0;
const maximumBytes = 1_000_000;
export function createCpSatCargoCapacitySolver(options: { python?: string; script?: string } = {}): CargoCapacitySolver {
  const python = options.python ?? process.env.WAB_SOLVER_PYTHON ?? "python3";
  const script = options.script ?? join(process.cwd(), "solver/cp_sat_solver.py");
  return { async solve(input) {
    const problem = structuredClone(validateCargoCapacityProblem(input));
    if (running >= 2) throw new Error("Cargo-capacity calculation is busy. Please retry.");
    running++;
    try {
      return await new Promise((resolve, reject) => {
        // Do not forward application/database credentials to this read-only worker.
        const child = spawn(python, [script], { stdio: ["pipe", "pipe", "pipe"], env: { PATH: process.env.PATH, NODE_ENV: process.env.NODE_ENV, PYTHONUNBUFFERED: "1" } });
        const output: Buffer[] = [];
        let bytes = 0, errorBytes = 0, settled = false;
        const finish = (error?: Error, value?: unknown) => {
          if (settled) return;
          settled = true;
          clearTimeout(timeout);
          if (error) { child.kill("SIGKILL"); reject(error); return; }
          try { resolve(validateCargoCapacityResult(problem, value)); } catch (e) { reject(e); }
        };
        const timeout = setTimeout(() => finish(new Error("Cargo-capacity worker exceeded its execution limit.")), (problem.timeLimitSeconds + 2) * 1000);
        child.stdout.on("data", (chunk: Buffer) => {
          bytes += chunk.length;
          if (bytes > maximumBytes) finish(new Error("Cargo-capacity worker exceeded its output limit."));
          else output.push(chunk);
        });
        child.stderr.on("data", (chunk: Buffer) => { errorBytes += chunk.length; if (errorBytes > maximumBytes) finish(new Error("Cargo-capacity worker exceeded its error-output limit.")); });
        child.on("error", () => finish(new Error("Cargo-capacity worker could not start.")));
        child.stdin.on("error", () => finish(new Error("Cargo-capacity worker input failed.")));
        child.on("close", code => {
          if (settled) return;
          if (code !== 0) { finish(new Error("Cargo-capacity worker failed.")); return; }
          try { finish(undefined, JSON.parse(Buffer.concat(output).toString("utf8"))); }
          catch { finish(new Error("Cargo-capacity worker returned unreadable output.")); }
        });
        child.stdin.end(JSON.stringify(problem));
      });
    } finally { running--; }
  } };
}
