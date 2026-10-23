# Repeated local calculation and request measurements

**Completed without failures or unproved/mismatched results.**

This compares the aligned V2 SQL reference in **local PGlite** with the same V2
CP-SAT model in a **local one-shot Python worker**. It does not measure native
hosted PostgreSQL/Supabase, the live legacy database function, a remote solver,
or the production flight workflow.

Recorded 182 measured requests across 7 scenarios, plus
14 separately recorded and excluded warm-ups. Every request
was executed serially. Engine order alternated by repetition. No outliers were
removed. Each successful response matched the sealed Step 3 result and passed
the server's independent resource/witness validator.

## Warm requests

10 measured requests per engine/case after one validated warm-up. The
HTTP/API and database session are reused. Python still starts a fresh process
for every solver request, matching the one-shot lifecycle of the current adapter.

| Case | DB calculation median | Solver calculation median | DB complete request median / p95 | Solver complete request median / p95 | Verified DB; solver |
| --- | ---: | ---: | ---: | ---: | --- |
| 01 | 9.354 s | 223.6 ms | 9.360 s / 9.457 s | 671.5 ms / 920.9 ms | 10/10; 10/10 |
| 02 | 4.809 s | 79.9 ms | 4.815 s / 4.831 s | 423.4 ms / 436.4 ms | 10/10; 10/10 |
| 03 | 1.395 s | 3.156 s | 1.398 s / 1.530 s | 3.502 s / 3.508 s | 10/10; 10/10 |
| 04 | 771.5 ms | 162.7 ms | 773.5 ms / 786.4 ms | 512.0 ms / 527.9 ms | 10/10; 10/10 |
| 05 | 165.5 ms | 476.2 ms | 167.0 ms / 175.7 ms | 826.6 ms / 852.0 ms | 10/10; 10/10 |
| 06 | 9.410 s | 207.9 ms | 9.416 s / 9.655 s | 688.1 ms / 936.5 ms | 10/10; 10/10 |
| 07-infeasible | 1.0 ms | 65.1 ms | 3.4 ms / 3.9 ms | 411.8 ms / 430.9 ms | 10/10; 10/10 |

## Fresh-session requests

3 requests per engine/case, each to a fresh measurement service and,
for SQL, a newly initialized PGlite instance. This is not an OS-cache-cold test.

| Case | DB calculation median | Solver calculation median | DB complete request median / p95 | Solver complete request median / p95 | Verified DB; solver |
| --- | ---: | ---: | ---: | ---: | --- |
| 01 | 9.509 s | 224.7 ms | 9.519 s / 9.571 s | 793.5 ms / 835.0 ms | 3/3; 3/3 |
| 02 | 4.929 s | 81.2 ms | 4.938 s / 4.998 s | 441.1 ms / 701.4 ms | 3/3; 3/3 |
| 03 | 1.492 s | 3.165 s | 1.500 s / 1.510 s | 3.525 s / 3.526 s | 3/3; 3/3 |
| 04 | 840.0 ms | 162.3 ms | 848.4 ms / 849.7 ms | 515.8 ms / 517.7 ms | 3/3; 3/3 |
| 05 | 216.0 ms | 475.9 ms | 224.6 ms / 224.7 ms | 828.7 ms / 837.4 ms | 3/3; 3/3 |
| 06 | 9.614 s | 197.0 ms | 9.625 s / 9.797 s | 661.4 ms / 819.7 ms | 3/3; 3/3 |
| 07-infeasible | 5.0 ms | 65.2 ms | 14.3 ms / 14.5 ms | 415.3 ms / 685.6 ms | 3/3; 3/3 |

## What the clocks include

- **Calculation only:** the complete capacity function call. SQL uses a
  clock_timestamp wrapper; Python uses a high-resolution monotonic timer around
  solve_capacity. Model construction, solving and result construction are
  included; startup, HTTP and process transport are excluded. PGlite's SQL clock
  has millisecond resolution in this run; values below that resolve as 0 ms and
  are displayed as <1 ms, not as a free calculation.
- **Complete local request:** client timing starts before HTTP request JSON
  encoding and ends after the response is received, parsed and compared with the
  expected result. It includes loopback HTTP transport, file input loading,
  hash/input checks, engine invocation, worker startup/imports and pipes,
  independent result validation and response handling.
- Python startup-to-ready and worker round-trip, input loading, backend call,
  validation and server-handler intervals are also recorded separately in
  results.json. Ready timing is observed at the parent's first ready message.
- Measurement-service launch, database initialization and SQL installation occur
  before the HTTP listener is ready. Their duration is recorded separately as
  serviceStartupMilliseconds and is **not charged to request latency**. Reused
  session startup values are not treated as independent warm samples.
- There are no live database input reads, authentication, live passenger/baggage
  preparation, WAN latency, browser rendering or concurrent-user load in this
  measurement. Frozen V2 inputs replace that preparation. The measurement wrapper
  invokes the unchanged model; it is not a production endpoint rollout.

Median is the middle observation (average of the two central observations for
even counts). p95 is nearest rank ceil(0.95*n). With 10 warm requests, p95 is the
observed maximum. Three fresh-session requests cannot establish a reliable tail
latency distribution. These are descriptive measurements on this machine, not
production latency guarantees.

## Limits, integrity and failures

Solver search limit: 10 seconds; process deadline:
12 seconds. SQL statement limit: 60
seconds, plus the external 65-second request deadline that can
terminate the isolated service. Startup is separately bounded at
20 seconds. Limits are ceilings, not measured durations.

Errors, FEASIBLE/UNKNOWN responses and mismatches remain visible in raw records
and summary.json; their timings are not represented as successful optimum
latencies. Count of exceptional responses, including warm-ups: 0.
Fresh replacement sessions are excluded from the warm latency distribution.

The original seven-case evidence is untouched. inputs/ contains the same
10-second execution payloads used in the successful Step 3 comparison. Exact
input and code hashes, runtime/hardware details and UTC start/finish timestamps
are in results.json. The source commit is the parent checkpoint; new measurement
files were uncommitted during execution. code/ archives the precise measured
sources, and SHA256SUMS seals this bundle.

No shared database changes, production integration, deployment, merge or push
were performed. **These measurements cannot substantiate a speed improvement
over the live legacy database or predict remote-service request time.**

## Reproduction

The run requires local loopback network permission and the configured runtimes.
From the repository root, use a new output directory:

```sh
node --import tsx solver/measure_cargo_capacity.mjs --run \
  --output /absolute/path/to/new-measurement-directory \
  --python /absolute/path/to/python-with-ortools --samples 10 --cold 3
node solver/report_cargo_capacity_measurement.mjs /absolute/path/to/new-measurement-directory
```

The report command only processes recorded data and never reruns calculations.
