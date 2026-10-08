# WAB AUTOLOAD solver

The application owns the aircraft rules and produces a solver-neutral `LoadPlanningProblem`. The adapter in `src/infrastructure/solver` passes that problem to this OR-Tools CP-SAT worker and independently validates the returned assignment.

## Local setup

```sh
python3 -m venv solver/.venv
solver/.venv/bin/python -m pip install -r solver/requirements.txt
```

Set `WAB_SOLVER_PYTHON` to the Python executable containing OR-Tools. For this local project use `$PWD/solver/.venv/bin/python`. The worker reads one JSON problem from standard input and writes one JSON solution to standard output, allowing it to move into a separate service without changing the domain contract.

## Checks

```sh
solver/.venv/bin/python -m unittest discover -s solver -p 'test_*.py' -v
solver/.venv/bin/python solver/benchmark_b747.py
```

The objectives are solved in operational priority order: minimise unloading-sequence inversions within each separately accessed cargo hold, approach Ideal Trim, then simplify the loading pattern. A correctly ordered block may slide within its hold to improve trim without incurring an unloading penalty. Position compatibility, maximum weights, locked assignments and physical-bay overlap are hard constraints.
