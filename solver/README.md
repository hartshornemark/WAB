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

## A350 capacity replacement: inactive first stage

The same worker accepts `mode: "CARGO_CAPACITY"` for type 359. This dispatch is
separate from the existing AUTOLOAD model. No application call site enables it.
The current database calculation and operational behaviour remain unchanged.

The contract and independent witness validator are in
`src/domain/cargo-capacity.ts`. Inputs contain a versioned snapshot identifier,
applicable candidate positions with hold-qualified physical bay IDs, whole-gram
net capacities, and an exact baggage-container reservation. Callers must derive
these candidates from validated configuration; the worker does not read D2/D3/D4
or any database. It selects non-overlapping pallet, cargo-container and reserved
baggage footprints, then maximises pallet count, cargo-container count and cargo
net weight in that order. A lower priority is attempted only after the previous
priority is proved optimal. If a later search times out, the previous feasible
witness is retained with `FEASIBLE`, never falsely labelled `OPTIMAL`.

These are footprint-capacity results, not a complete published cargo offer or
actual load placement. Aggregate hold weights, remaining aircraft payload, Bulk
capacity, configuration applicability and actual baggage fit must still be
applied and verified by the integration layer. The new third objective optimises
the complete cargo witness weight; the legacy SQL tie-break considers pallet
weight. Differences between equal-count arrangements must be reconciled before
rollout, not accepted as an unexplained increase in capacity.

The server-only adapter limits each process to two active capacity workers,
bounds input and output, adds a hard process timeout and forwards no database
credentials. Deployment-wide admission control is still required before rollout.
The returned revision must match the request, and the caller must also confirm
that the snapshot is still current before displaying a result. There is no
cache, live-read replacement, UI activation or migration in this stage.

Run the offline benchmark with the same configured Python runtime:

```sh
solver/.venv/bin/python solver/benchmark_cargo_capacity.py
```

It runs ten fresh processes for each baggage reservation (0, 5, 34, 35), plus ten
requests with two concurrent workers, on the captured A350 D3 fixture. Timings
include Python/OR-Tools startup and output parsing, but exclude live database
reads, API transport and browser rendering. This fixture is not a fresh snapshot
of ZZ9350 24OCT. The benchmark verifies resource exclusivity and reservation/net
totals for every returned witness. Unit tests compare small cases against an
independent exhaustive oracle and exercise unavailable workers, malformed/stale
responses, execution limits and concurrency limits.

Initial local measurements are recorded in
[`benchmarks/a350-capacity-2026-10-23.json`](benchmarks/a350-capacity-2026-10-23.json),
including runtime versions and individual samples. For five reserved baggage
ULDs, ten startup-inclusive runs had a median of 352.35 ms and a 95th percentile
of 358.16 ms. Ten requests with two concurrent workers had a 95th percentile of
400.31 ms. Every feasible fixture run proved all three objectives optimal;
35 reserved containers was proved infeasible. These small offline samples are
preliminary evidence, not production acceptance or a live SQL speedup comparison.

Remaining work before activation:

1. Obtain versioned raw inputs without invoking the legacy cargo-capacity search;
   retain carrier permissions and consistent baggage/configuration snapshots.
2. Preserve the current cargo-offer contract, reconcile the weight tie-break,
   apply aggregate limits, and independently validate the resulting offer.
3. Load the board/tray independently of offer calculation, with explicit
   unavailable/stale/unproved states. Keep the legacy route available for review.
4. Benchmark both implementations on identical current flight snapshots,
   including complete request times, cold starts, failures and concurrent users.
5. Review database changes and deployment readiness with the user before any
   migration, activation, merge or deployment.

Deployment packaging must include both `cp_sat_solver.py` and
`cargo_capacity.py`, and a compatible pinned OR-Tools runtime. Normal AUTOLOAD
requests do not import the capacity module.
