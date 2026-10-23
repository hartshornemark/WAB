"""Single-use hosted timing wrapper. No configuration or database credentials."""
import json
import sys
import time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from cargo_capacity import solve_capacity

print(json.dumps({"readyAtNanoseconds": time.perf_counter_ns()}), flush=True)
p = json.load(sys.stdin)
started = time.perf_counter_ns()
r = solve_capacity(p)
print(json.dumps({"result": r, "calculationMilliseconds": (time.perf_counter_ns() - started) / 1_000_000}), flush=True)
