"""Measurement-only one-shot wrapper; production solver/model is unchanged."""
import json
import sys
import time
from cargo_capacity import solve_capacity

print(json.dumps({"ready": True}), flush=True)
problem = json.load(sys.stdin)
started = time.perf_counter_ns()
result = solve_capacity(problem)
calculation_ms = (time.perf_counter_ns() - started) / 1_000_000
print(json.dumps({"result": result, "calculationMilliseconds": calculation_ms}), flush=True)
