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

## A350 capacity replacement: inactive version 2

The worker accepts `mode: "CARGO_CAPACITY"` for type 359 with the explicit
`A350_MAX_NET_CARGO_V2` contract. No application call site enables it. The live
database and existing AUTOLOAD behaviour remain unchanged.

The authoritative [calculation rules](../docs/a350-cargo-capacity-rules.md)
define one objective: maximum permissible net ULD plus Bulk cargo. Baggage and
other reservations, ULD tare, physical footprints, area and parent limits, Bulk
space/density and the aircraft weight allowance constrain every arrangement.
There is no pallet-count priority. Missing configuration is rejected.

The contract and independent witness validator live in
`src/domain/cargo-capacity.ts`. The worker reads no database or D2/D3/D4 records;
callers must supply applicable, versioned configuration and prepared baggage
requirements. Results distinguish proven optimum, feasible, infeasible and
unknown. A feasible witness alone does not establish the maximum.

The offline database reference loads `reference/max_net_cargo_v2.sql` first
(retained exhaustive oracle and flow evaluator), then
`reference/frontier_net_cargo_v2.sql` (optimized public entry point within the
isolated reference schema). It rejects obvious impossibilities and combines
exact, reduced compartment/hold capacity regions. No migration or production
function is installed. Both implementations use the same validated V2 inputs.
[Exactness and preparation status](../docs/a350-capacity-reference-exactness.md)
describes the small-case oracle checks and resource/configuration error guards.
The frozen version-1 flight/scenario artifacts remain immutable. Their sourced
enrichment is sealed in `tests/fixtures/cargo-capacity/passenger-scenarios-v2`;
both components receive the same input file per case. All seven now pass the authorised correctness comparison, with equal proven
maxima in cases 1–6 and matching proven infeasibility in case 7. The
[sealed results](verification/a350-v2-seven-scenarios-2026-10-23/README.md)
record exact inputs, full validated witnesses, budgets and earlier inconclusive
attempts. No timing benchmark or live database activation has been performed.

The server-only adapter admits at most two active capacity workers per process,
bounds input/output and execution, forwards no database credentials, and checks
returned revision and feasibility. Deployment-wide admission and snapshot
freshness checks remain integration requirements. There is no live activation,
cache or migration in this stage.

Run unit checks with:

```sh
node --conditions=react-server --import tsx --test tests/cargo-capacity.test.ts tests/cargo-capacity-frontier.test.ts
solver/.venv/bin/python -m unittest discover -s solver -p 'test_*.py' -v
```

The 16 synthetic examples test individual calculation rules; they are not the
seven frozen passenger-scenario result comparisons or timing benchmarks.

For a subsequently authorised benchmark, the script requires a validated V2
input file and refuses implicit upgrades of old snapshots:

```sh
solver/.venv/bin/python solver/benchmark_cargo_capacity.py --input /absolute/path/to/v2-input.json --samples 10
```

Historical measurements in
[`benchmarks/a350-capacity-2026-10-23.json`](benchmarks/a350-capacity-2026-10-23.json)
measure the superseded pallet-first prototype. They cannot establish V2
performance or a like-for-like database speed improvement. No new scenario or
performance benchmark is included in Step 2.

Before activation, source complete V2 snapshots, compare both implementations on
the frozen scenarios, measure component and complete request performance, review
failure/concurrency behaviour, and preserve the cargo-offer API and independent
board/tray availability. Migration, activation, merge and deployment require
explicit approval.

Deployment packaging must include both `cp_sat_solver.py` and
`cargo_capacity.py`, and a compatible pinned OR-Tools runtime. Normal AUTOLOAD
requests do not import the capacity module.

## Reproduce the authorised seven-case correctness check

Use a new output directory; the runner never edits frozen fixtures or accesses
the shared database. Child execution/output are bounded. These are correctness
limits, not comparable timing measurements:

```sh
node --import tsx solver/verify_cargo_capacity.mjs --run \
  --output /absolute/path/to/new-attempt-directory \
  --python /absolute/path/to/python-with-ortools \
  --solver-seconds 10 --database-seconds 60
```
