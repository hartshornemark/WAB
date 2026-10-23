# A350 hosted comparison — existing DigitalOcean app and Supabase database

Deployment runbook. Execution began with explicit user approval on
23 October 2026: the preparation branch is pushed and the private benchmark
schema/account are installed on current Supabase. Hosting and benchmark outcomes
must be recorded separately; instructions below do not themselves prove completion. This replaces the earlier proposal for a separate private service and
separate reference database. The operational cargo calculation, AUTOLOAD, board,
tray and other aircraft are unchanged.

## Confirmed target and prepared configuration

User-supplied App Spec: `wabiqa-app`, `https://demo.wabiqa.com`, region `sgp`;
service `wab`, port 3000, two `apps-s-1vcpu-1gb` instances. It builds
`hartshornemark/WAB` branch `staging` with `deploy_on_push: true`.

Python and OR-Tools already run as child processes inside the app container.
The new gated benchmark route launches `solver/staging/app_worker.py` locally.
There is no new service, port, route to another backend, instance or database.
The existing image adds the pinned psycopg driver for the DATABASE test path.
Each request selects only one of seven sealed A350 cases and DATABASE or SOLVER.
It cannot select flights, load plans or arbitrary inputs. Both engines receive
the same sealed input; the app independently validates arrangements and compares
proven results with the sealed Step 3 maxima/infeasibility.

`wabiqa-app.capacity-review.patch` is a review patch against the supplied upload,
not a directly submittable App Spec. It changes the app's source to
`fix/a350-solver-cargo-capacity`, disables automatic deployment, and adds the
settings below with testing OFF. It preserves the existing two app instances,
region, domain, ingress and public Supabase variables. It contains no existing
Supabase key. The earlier separate-service fragment, container and HTTP service
have been removed so they cannot accidentally be used as the current plan.

Re-export the live App Spec before applying the patch to a local copy. Reconcile
intervening changes and retain the original spec, deployed commit and rollback
ID. Do not push to `staging`, which currently triggers deployment automatically.
The reviewed preparation branch must be pushed before hosting can build it;
push and deployment require explicit approval.

## Runtime settings on existing `wab` service

| Name | Value |
| --- | --- |
| `WAB_DEPLOYMENT_ENV` | `staging` |
| `WAB_CAPACITY_TESTS_ENABLED` | initially `false` |
| `WAB_CAPACITY_TEST_TOKEN` | operator secret, 32+ characters |
| `CAPACITY_DATABASE_URL` | restricted `capacity_benchmark` connection to the current Supabase project |
| `CAPACITY_DATABASE_CA_FILE` | optional mounted CA bundle path to override the packaged provider CA bundle |
| `CAPACITY_RELEASE_ID` | `${_self.COMMIT_HASH}` |

Replace secret placeholders in the hosting secret store; never submit them as
real configuration. Do not paste passwords/tokens into chat, Git, shell history,
results or NEXT_PUBLIC variables. No backend service token/URL is needed.

Database URL: direct `db.ffmadtrcirrzywdqahbu.supabase.co` with user
`capacity_benchmark`, or the project's actual session pooler hostname with user
`capacity_benchmark.ffmadtrcirrzywdqahbu`, port 5432. Database name is `postgres`.
Get the actual endpoint from Supabase Connect; do not invent its region hostname.
Use a URL-encoded password and no query-string options. The worker enforces TLS
certificate/hostname validation, a five-second connection timeout, read-only
sessions, a 60-second statement timeout and one-second lock timeout. Transaction
pooling on port 6543 is rejected. The actual verified session endpoint for this project is
`aws-0-ap-northeast-2.pooler.supabase.com:5432`. The provider CA from the project's
Database Settings is packaged as `solver/staging/supabase-ca.crt` and is used by
default. It was downloaded on 23 October 2026 from
`https://supabase-downloads.s3-ap-southeast-1.amazonaws.com/prod/ssl/prod-ca-2021.crt`.
Its SHA-256 certificate fingerprint is
`80:70:25:AD:50:D4:ED:21:9D:2C:9C:7D:29:9C:00:4F:82:4E:B0:0C:F7:F6:5A:FE:F6:07:D0:7B:72:E6:CA:FA`.
It expires 26 April 2031. Certificate and hostname validation remain mandatory;
refresh the packaged certificate through review if the provider rotates it.
A native restricted-role connection and the infeasible smoke calculation passed
from this workstation; repeat through the deployed endpoint before measurement.

The SOLVER child receives no database URL, operator token or app credentials.
Only the DATABASE child receives the restricted database URL/optional CA path.
Neither gets the complete app environment. No Supabase service-role key is used.

## Private benchmark SQL — installation procedure

The existing database is acceptable to the user. Its shared CPU/memory is not a
blocker. Benchmark objects live exclusively in `capacity_reference`, outside
operational functions/tables. Do not expose this schema through the Data API.

Before installation, confirm the connected project is
`ffmadtrcirrzywdqahbu`, record its Postgres version/compute/region and inspect
existing schema/role names and Data API exposure. The prepared preflight aborts
if `capacity_reference` or `capacity_benchmark` already exists; do not overwrite
unknown objects or bypass that check. The database name alone does not identify
a Supabase project, so the operator must confirm the project endpoint.

After explicit approval, an administrator runs these five files in ONE
transaction using a securely supplied operator-only connection URL:

```sh
psql "$CAPACITY_REFERENCE_OWNER_URL" --single-transaction -v ON_ERROR_STOP=1 \
  -f solver/staging/preflight.sql \
  -f solver/reference/max_net_cargo_v2.sql \
  -f solver/reference/frontier_net_cargo_v2.sql \
  -f solver/staging/timed_offer.sql \
  -f solver/staging/runtime_grants.sql
```

The two reference files are the unchanged versions proven in Step 3. Their
historical offline-only comments describe their original use; this reviewed
wrapper now prepares installation in a private schema on current Supabase.
Functions calculate only from supplied JSON, without querying flight records.
The installation creates a NOLOGIN, NOINHERIT role with no elevated privileges or
memberships, revokes schema/function access from PUBLIC and API roles, and grants
only schema usage/function execution to `capacity_benchmark`. It changes no
operational table, function or default privileges for unrelated future objects.
All installation changes roll back on failure. The private functions also have
`search_path=pg_catalog` pinned; no frozen calculation body is changed.

In a secure administrator session, enable LOGIN for this new role and set its
password using a secure interactive/password-management method; do not put the
password into a committed SQL file. Set the resulting restricted URL in the
existing app's encrypted runtime variables. The worker checks its actual current
role/database, read-only status, absence of elevated privileges/memberships,
absence of public-schema CREATE and ownership of benchmark functions before
running any reference calculation. If these checks fail, investigate; do not
relax operational schema permissions to make the test pass. Run Supabase security
advisors after the approved installation and verify API roles cannot access the
schema/functions. The approved installation has been executed directly; it does not alter the
shared application migration history or operational objects.

## Test execution after approved deployment

1. Record the current spec/rollback deployment. Review and approve the source,
   SQL install, secrets and deployment. No new resources or paid component.
2. Build the existing Dockerfile from the reviewed branch. Deploy the existing
   app with the test flag OFF and the required runtime variables. Confirm 404
   while off, then enable staging testing and confirm 401 without the token.
3. Agree a quiet AUTOLOAD window and send requests serially across BOTH replicas.
   The endpoint admits only one test per Node process; it is not a distributed
   lock and does not block AUTOLOAD. No operational scheduling logic is changed.
   If AUTOLOAD is needed, pause the test caller first. Record the number of
   replicas, CPU/RAM, image commit, Python/OR-Tools/Postgres versions, database
   resources, client location, background activity and provider timeout limits.
4. Run the infeasible case smoke pair with `WAB_CAPACITY_TEST_TOKEN` in the
   caller's environment (never on the command line):

   ```sh
   node solver/run_hosted_capacity_measurements.mjs --run --smoke \
     --cases case-07-infeasible --url https://demo.wabiqa.com \
     --output /absolute/path/to/new-smoke-results
   ```

   This checks authenticated routing, local Python/driver packaging, database
   TLS/permissions, reference installation, fixed-input integrity and validation.
   Inspect per-instance memory, CPU, restarts/OOM and normal app responsiveness.
5. Only after smoke passes, run the seven cases:

   ```sh
   node solver/run_hosted_capacity_measurements.mjs --run \
     --url https://demo.wabiqa.com \
     --output /absolute/path/to/new-results --samples 10
   ```

   The caller alternates engines and saves warm-ups separately. Use
   `--first-request` for a separately labelled sample after an actual deployment
   or observed inactivity. It does not simulate cold hosting or restart services.
6. Revalidate results and report calculation-only, worker startup, app-to-worker
   execution round trip and complete external HTTPS latency separately. DATABASE
   execution includes connection/TLS/readiness/database transport; its SQL core
   time excludes them. SOLVER startup includes imports and fixed-case verification;
   its core includes model construction/search. Per-request validation is outside
   each engine's core and inside the external request. These shared app resources
   are the intended reuse topology; there is no artificial backend HTTP hop.
7. Disable the flag after the experiment. Timeouts, unproved maxima, failures and
   mismatches are exceptions, never successful optimal results.

The fixture inputs replace live passenger retrieval/baggage preparation. This is
an aligned fixed-input comparison on intended hosting, not a live operational
cutover or a claim about the superseded legacy SQL rules. Ongoing operational
reuse still needs shared admission across AUTOLOAD/capacity jobs and hosted
concurrency/headroom checks. Local individual workers measured approximately
90–93 MiB on macOS; that is not spare-memory evidence for the deployed 1GB app.

## Rollback and cleanup

Set the test flag false and restart/redeploy the existing app so it rereads the
environment. Restore its saved source/spec/deployment if required. No additional
service needs deleting. No operational workflow depends on the benchmark.

For database retirement, first disable role LOGIN and remove the restricted URL
from the app, then terminate any remaining benchmark-role sessions using approved
administrative controls. After confirming the schema/role belong solely to this
installation, drop ONLY `capacity_reference` and `capacity_benchmark`. The latter
must have no unrelated dependencies; inspect them before cleanup. Never drop the
`postgres` database or use broad cleanup against public/operational schemas.

## Validation boundary

Local checks exercise feature/auth gates, sealed-input restrictions, independent
witness validation, admission/error recovery, sanitized child environments,
bounded worker I/O, native connection options and role/readiness rejection.
The existing app production build must package the one-shot worker, model,
fixtures and pinned PostgreSQL driver. Local SQL tests check private-schema
permissions and calculation under the restricted role where supported.

No Docker engine or DigitalOcean CLI is available on this workstation. Container
builds, live Supabase install/TLS/role checks, DigitalOcean validation, actual
headroom and hosted smoke/latency measurements remain deployment-time checks.
Do not describe local preparation as a verified hosted deployment.

References:
- [Supabase connection methods](https://supabase.com/docs/guides/database/connecting-to-postgres)
- [Supabase roles](https://supabase.com/docs/guides/database/postgres/roles)
- [DigitalOcean App Spec](https://docs.digitalocean.com/products/app-platform/reference/app-spec/)

Local verification on 23 October 2026: 938 TypeScript tests (including the real
one-shot solver smoke), 20 Python tests, TypeScript checking, changed-file lint
and the production Next.js build passed. The seven sealed V2 inputs reproduce
unchanged. The review patch was applied to a redacted reconstruction of the
supplied App Spec and parsed as YAML: one existing service and its original
resource allocation remain. Local SQL tests use PGlite, not the live Supabase
server. Native TLS, provider permissions and container build remain unexecuted.

Hosted execution uncovered a harness timing issue in the initial run: solver
imports took about four seconds, while the original 12-second process deadline
included both imports and the sealed ten-second search budget. Initial results,
including case-3 failures, are preserved as an interrupted attempt. The corrected
worker allows at most 15 seconds for startup and then the unchanged search budget
plus two seconds for result delivery (at most 12 seconds). The DATABASE process
limit stays 68 seconds, its statement limit 60 seconds and the external caller
limit 80 seconds. No calculation rule, input, objective or search budget changed.
The final complete comparison must be rerun on the corrected revision; do not
combine the interrupted attempt's timings with the final run.
