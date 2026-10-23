# Case 3 incumbent and optimality timing

The existing authenticated, staging-only fixture endpoint accepts
`{"caseId":"case-03","engine":"SOLVER","profileCase3":true}`. Other cases,
engines, false/non-boolean profile values and arbitrary input remain rejected.
Without the optional flag, the ordinary solver path has no callback.

The passive callback records strict objective improvements in memory. It adds
no constraints, hints, early stopping or bound callback and does not change the
sealed input, single search worker, seed or ten-second calculation limit. Model
construction and profiling preparation both count against that existing limit.
The Python file changes to expose an optional observer; model-proto hashes are
compared in a real Case 3 test to verify the same model with and without it.

Times use monotonic milliseconds from calculation start (validation/model
construction included, imports excluded). `firstValidMilliseconds` is the first
incumbent callback. `bestFoundMilliseconds` is the first callback attaining the
eventual returned net cargo objective, not the last equally good arrangement.
That objective is only known to be maximum when independently established.
`proofMilliseconds` is the observation of OPTIMAL when solve returns, so it
includes return overhead rather than claiming the exact internal proof instant.
When time expires without proof, proof time is null and
`proofCensoredAtMilliseconds` records the observation deadline; it is not a
successful proof timing. The final bound and gap are preserved.

Process CPU time, solver wall time, deterministic search effort, branches and
conflicts support comparison of CPU consumption and elapsed time. They do not
identify host throttling or other causes by themselves. Callback overhead can
affect timings, so the caller alternates serial ordinary/profile pairs after
one excluded warm-up each. Keep every run, including inconclusive proofs.

Run `node solver/run_case3_progress.mjs --run --url https://demo.wabiqa.com
--output <new-directory> --samples 10`, with the existing operator token supplied
through `WAB_CAPACITY_TEST_TOKEN`. Check deployed revision/input hashes and
independently validate returned arrangements. Disable the benchmark gate again
after measurement. No operational fallback or cargo workflow is activated.

Callback/status reference: [OR-Tools CP-SAT documentation](https://developers.google.com/optimization/cp/cp_solver).
