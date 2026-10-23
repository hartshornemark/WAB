"""Offline benchmark: includes process startup, reports validated fixture witnesses."""
import concurrent.futures
import json
import math
from pathlib import Path
import platform
import statistics
import subprocess
import sys
import time
import ortools
from test_cargo_capacity import a350_problem, check_witness

worker = Path(__file__).with_name("cp_sat_solver.py")


def run(baggage):
    problem = a350_problem(baggage)
    started = time.perf_counter()
    child = subprocess.run([sys.executable, str(worker)], input=json.dumps(problem), text=True, capture_output=True, timeout=5, check=True)
    total = (time.perf_counter() - started)*1000
    result = json.loads(child.stdout)
    if result["arrangement"]:
        check_witness(problem, result)
    return {"totalMs": round(total, 2), **result}


def summary(label, results):
    times = sorted(r["totalMs"] for r in results)
    return {"case": label, "samples": len(times), "medianMs": round(statistics.median(times), 2), "p95Ms": times[max(0, math.ceil(.95*len(times))-1)], "worstMs": max(times), "statuses": sorted(set(r["status"] for r in results)), "measurements": [{"totalMs": r["totalMs"], "solveMilliseconds": r["solveMilliseconds"], "status": r["status"], "provedObjectives": r["provedObjectives"]} for r in results], "witnesses": [{"pallets": len(r["arrangement"]["palletPositionIds"]), "cargoContainers": len(r["arrangement"]["containerPositionIds"]), "baggageContainers": len(r["arrangement"]["baggagePositionIds"])} if r["arrangement"] else None for r in results]}


if __name__ == "__main__":
    report = {"scope": "Offline captured A350 configuration; not live RPC or browser timings", "environment": {"python": platform.python_version(), "ortools": ortools.__version__, "platform": platform.platform(), "workersPerSolve": 1, "timeLimitSeconds": 2}, "cases": []}
    for baggage in (0, 5, 34, 35):
        report["cases"].append(summary(f"baggage-{baggage}", [run(baggage) for _ in range(10)]))
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        report["cases"].append(summary("two-concurrent-workers-baggage-5", list(pool.map(run, [5]*10))))
    print(json.dumps(report, indent=2))
