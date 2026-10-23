# Six-second total request experiment — tests only

User authorised a six-second TOTAL target for testing, with the calculation
rules unchanged. This applies only to the gated, authenticated staging fixture
endpoint, never the operational cargo offer, AUTOLOAD or a saved flight plan.
Request: `{"caseId":"case-03","engine":"SOLVER","totalBudgetMilliseconds":6000}`.
The existing optional Case 3 progress flag may be combined with it. DATABASE
and other budget values are rejected.

The caller measures HTTPS request-to-complete-response time and aborts at six
seconds. The server uses a 5,500 ms deadline from handler entry, leaving 500 ms
for transport. It reserves another 250 ms inside that budget for solver return,
result decoding and independent validation. Network transit cannot be guaranteed
by a server timer, so report actual measured times and client deadline failures.

The worker receives the sealed input as one line, imports dependencies, then
signals readiness. Only then does the parent send the remaining calculation
allowance. Startup therefore consumes the total budget rather than receiving a
separate allowance. Python can only narrow the original calculation limit; the
fixture, input hash, model constraints, objective, seed and worker count are
unchanged. The parent kills a stalled worker at the server deadline.

If the returned arrangement passes the independent validator, publish that
result to the test response. `PROVEN_MAXIMUM` requires OPTIMAL and the known
reference objective; `VALID_UNPROVEN` means a valid incumbent with no maximum
claim. INFEASIBLE is separately `PROVEN_INFEASIBLE`. No valid result in time is
`NO_VALID_RESULT`, with no invented zero-capacity offer. Invalid witnesses and
worker errors remain failures. Existing requests without the optional test
budget keep their original bounded execution path.

Run `node solver/run_six_second_tests.mjs --run --url https://demo.wabiqa.com
--output <new directory> --samples 3` with the existing operator token supplied
through `WAB_CAPACITY_TEST_TOKEN`. All seven cases are serial; each has one
excluded warm-up and three measured requests. Preserve deadline misses,
incomplete results and suboptimal valid offers. Independently validate every
returned arrangement and compare net cargo, proof state and actual total time
with the frozen reference. Disable testing again afterwards.

Execution on 23 October 2026: all 21 measured requests (three per case) returned
within six seconds and matched the reference outcome/net cargo. Four were valid
but unproved: three Case 3 and one Case 5. Longest measured request: 5.601 s.
All returned arrangements passed independent validation. Testing was disabled
again; operational planning remains unchanged. See the [full test report](../solver/benchmarks/a350-six-second-total-hosted-2026-10-23/REPORT.txt).
