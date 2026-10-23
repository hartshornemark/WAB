"""Opt-in V2 worker benchmark. Frozen V1 core-only cases are never upgraded implicitly."""
import argparse
import json
from pathlib import Path
import statistics
import subprocess
import sys
import time
from cargo_capacity import validate_problem, RULES

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Requires an explicitly enriched, frozen V2 offer input. Do not run until the measurement step is authorised.')
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--samples', type=int, default=10)
    args = parser.parse_args()
    if not 1 <= args.samples <= 100:
        parser.error('samples must be between 1 and 100')
    problem = json.loads(args.input.read_text())
    validate_problem(problem)
    measurements = []
    for _ in range(args.samples):
        started = time.perf_counter()
        child = subprocess.run([sys.executable, str(Path(__file__).with_name('cp_sat_solver.py'))], input=json.dumps(problem), text=True, capture_output=True, timeout=problem['timeLimitSeconds']+2, check=True)
        measurements.append({'totalMilliseconds': round((time.perf_counter()-started)*1000, 2), 'result': json.loads(child.stdout)})
    print(json.dumps({'rulesVersion': RULES, 'scope': 'Worker startup included; database and browser excluded', 'inputRevision': problem['inputRevision'], 'samples': measurements, 'medianMilliseconds': statistics.median(r['totalMilliseconds'] for r in measurements)}, indent=2))
