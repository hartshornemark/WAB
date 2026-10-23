"""Explicit, temporary console diagnostic; never imported by the app route.

Same sealed Case 3 model/data, with a separately declared 30-second calculation
ceiling, to observe proof completion beyond the ordinary ten-second limit.
The in-process solve interception changes only the time parameter and is
restored after every run. No app files, environment or database are modified.
"""
import base64
import hashlib
import importlib.metadata
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import signal
import sys
import time
from unittest.mock import patch
import zlib


def main():
    if sys.argv[1:] != ['--run']:
        raise SystemExit('Explicit --run required for three Case 3 diagnostics')
    root = Path(os.environ.get('CAPACITY_REPO_ROOT', '/app')) / 'solver'
    sys.path.insert(0, str(root))
    from cargo_capacity import solve_capacity
    from staging.app_worker import fixed_case
    from staging.search_profile import SearchProfile
    from ortools.sat.python import cp_model
    raw = (root / 'verification/a350-v2-seven-scenarios-2026-10-23/final/inputs/case-03.json').read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    problem = fixed_case({'caseId': 'case-03', 'engine': 'SOLVER', 'inputSha256': digest, 'problem': json.loads(raw)})
    original = cp_model.CpSolver.solve
    rows = []
    started_at = datetime.now(timezone.utc).isoformat()
    for repetition in range(1, 4):
        observer = SearchProfile()
        settings = {}
        def diagnostic_solve(solver, model, callback=None):
            settings.update(searchWorkers=solver.parameters.num_search_workers, randomSeed=solver.parameters.random_seed)
            solver.parameters.max_time_in_seconds = max(0.001, 30 - (time.perf_counter() - observer.started))
            return original(solver, model, callback)
        # Independent hard ceiling; interrupted diagnostic cannot run unbounded.
        signal.alarm(35)
        try:
            with patch.object(cp_model.CpSolver, 'solve', diagnostic_solve):
                result = solve_capacity(problem, observer=observer)
        finally:
            signal.alarm(0)
        rows.append({'repetition': repetition, 'result': result, 'searchProfile': observer.report(result), 'settings': settings})
    report = {'scope': 'Separate console diagnostic, not part of the repeated ten-second benchmark or HTTP latency comparison',
              'startedAt': started_at, 'finishedAt': datetime.now(timezone.utc).isoformat(),
              'caseId': 'case-03', 'inputSha256': digest, 'sealedInputTimeLimitSeconds': problem['timeLimitSeconds'],
              'effectiveDiagnosticCalculationLimitSeconds': 30, 'hardLimitSecondsPerRun': 35,
              'revision': os.environ.get('CAPACITY_RELEASE_ID'), 'instance': os.uname().nodename,
              'architecture': os.uname().machine, 'pythonVersion': sys.version.split()[0], 'ortoolsVersion': importlib.metadata.version('ortools'),
              'modelSha256': hashlib.sha256((root / 'cargo_capacity.py').read_bytes()).hexdigest(),
              'processMode': 'One interpreter, three fresh models/solvers; imports excluded', 'rows': rows}
    payload = base64.b64encode(zlib.compress(json.dumps(report).encode())).decode()
    # Short numbered lines survive terminal wrapping; contains benchmark data only.
    for index, offset in enumerate(range(0, len(payload), 52)):
        print(f'C3PROOF:{index:03d}:{payload[offset:offset+52]}', flush=True)
    print('C3PROOF_DONE', flush=True)


if __name__ == '__main__':
    main()
