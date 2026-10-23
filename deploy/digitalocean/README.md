# A350 staging integration — DigitalOcean App Platform

Preparation only. No app, database, secret, deployment, GitHub branch or hosting
resource has been changed. The operational cargo calculation, board, tray and
AUTOLOAD call sites remain as before. This package exposes **only seven fixed
A350/359 test cases**, never an arbitrary aircraft, flight, payload or placement.

## Prepared components

- Existing Next.js app: `POST /api/internal/a350-capacity` is absent (404) unless
  both staging environment and the explicit test flag are set. It requires a
  server-only operator bearer token, accepts only `{caseId, engine}`, loads the
  sealed Step 3 inputs, verifies their hashes and independently validates returned
  arrangements. Requests are serially admitted per app process and never cached.
- New private `a350-capacity` service: `solver/staging/Dockerfile`, Python 3.12,
  pinned OR-Tools 9.14.6206 and psycopg 3.3.6. A separate backend token protects
  `/v1/capacity`. It accepts only byte-equivalent verified cases, launches a
  bounded single-use solver or calls native PostgreSQL, and reports timings.
  One calculation is admitted per service process. Deploy **one replica** for
  the controlled test. This is not deployment-wide production admission control.
- Native PostgreSQL reference: exact versioned SQL in a **separate empty database
  named `capacity_staging_reference`**, using a non-admin `capacity_reader` role
  with schema usage/function execution only and read-only connections. `/healthz`
  refuses readiness if the role/database/function requirements are missing.
- The main Dockerfile now packages the required capacity module and seven fixture
  inputs explicitly; standalone tracing alone cannot discover dynamic file reads.
- `solver/run_hosted_capacity_measurements.mjs` sends serial authenticated staging
  requests, alternates engine order, records warm-ups/results/transport timings,
  and never prints tokens. It does not change an operational plan.

The App Platform component fragment is **not a complete app specification**.
Merge it into a saved copy of the existing staging spec. Do not submit it as a
replacement spec: it omits the current app, routes, domains and existing services.
No public route or `http_port` is assigned to the backend. Automatic deployment
for that component is disabled. Its healthcheck uses internal port 8080.

## Information still required before a deployment decision

1. Exact staging app ID/name, URL, current app specification and deployment commit.
   Only the provider and App Platform product have been confirmed so far.
2. The backend's intended CPU/RAM instance size and region, recorded for testing.
   No paid database/service or resource size has been invented/provisioned.
3. Approved isolated native PostgreSQL host, region/tier and database credentials.
   The app currently uses Supabase. **Do not assume a new DigitalOcean PostgreSQL
   host represents that existing database's performance.** Match the intended
   database location/resources, or explicitly label the test as a different hosted
   reference. This package does not install anything in the shared Supabase
   `postgres` database. The schema/name guard deliberately prevents that.
4. Separate operator/backend secrets (32+ characters), kept in runtime encrypted
   variables. Neither goes in Git, NEXT_PUBLIC variables, a browser, an app spec
   committed with real values, shell history or results/logs.

## Staging-only variables

Existing app, runtime variables:

| Name | Value |
| --- | --- |
| `WAB_DEPLOYMENT_ENV` | `staging` |
| `WAB_CAPACITY_TESTS_ENABLED` | initially `false`, enable only for the approved test |
| `WAB_CAPACITY_TEST_TOKEN` | operator secret |
| `WAB_CAPACITY_SERVICE_TOKEN` | different backend secret |
| `WAB_CAPACITY_SERVICE_URL` | `http://a350-capacity:8080` |

Backend, runtime variables:

| Name | Value |
| --- | --- |
| `WAB_DEPLOYMENT_ENV` | `staging` |
| `PORT` | `8080` |
| `CAPACITY_SERVICE_TOKEN` | same backend secret as app; never operator token |
| `CAPACITY_DATABASE_NAME` | `capacity_staging_reference` |
| `CAPACITY_DATABASE_URL` | native PostgreSQL URL for restricted runtime role; use TLS and the provider CA settings |
| `CAPACITY_RELEASE_ID` | `${_self.COMMIT_HASH}` (App Platform build commit) |

Do not replace the existing app's public Supabase build/runtime variables.
The new database URL belongs only to the backend. The model subprocess receives
neither token nor any database credential. No service-role key is used.

## Concrete deployment sequence — not executed

1. Export/review the current staging spec and record its rollback deployment.
   Preserve all current app configuration. Confirm that pushing the preparation
   branch will not trigger an unintended deployment of an existing component.
2. Review the proposed commit, resources, secrets and isolated database target.
   **Get explicit approval before pushing, creating resources, applying SQL or
   deploying.** User authorization so far is preparation, not these actions.
3. Have the database administrator create the isolated database and a NORMAL,
   non-owner/non-superuser `capacity_reader` account. Its password is entered
   through the database/hosting secret store; do not paste it into SQL files.
4. As the owner of that isolated database, install all files in a single
   transaction. `CAPACITY_REFERENCE_OWNER_URL` is an operator-only environment
   secret and is never given to a service or committed:

   ```sh
   psql "$CAPACITY_REFERENCE_OWNER_URL" --single-transaction -v ON_ERROR_STOP=1 \
     -f solver/reference/max_net_cargo_v2.sql \
     -f solver/reference/frontier_net_cargo_v2.sql \
     -f solver/staging/timed_offer.sql \
     -f solver/staging/runtime_grants.sql
   ```

   The grants script refuses any other database name or an elevated runtime
   role. A failure rolls back the entire installation. No operational table is
   read or changed. Verify with the runtime URL: transaction_read_only is on,
   current_database is correct, and capacity_reference.timed_offer exists.
5. Build the app's existing Dockerfile and the backend Dockerfile from the same
   reviewed commit. Create/merge the backend component into the existing staging
   app without a public route. Keep the app test flag off initially. Retain the
   reviewed branch/source and disable automatic deployment during the experiment.
6. Check backend `/healthz` internally. Confirm native PostgreSQL version,
   restricted role, expected release and seven fixture hashes. Check that the
   public app endpoint returns 404 while off, 401 without the operator token when
   enabled, and that an invalid case cannot execute a calculation.
7. Enable the flag on **staging only** and run one smoke pair (case 7) before the
   repeated measurement. The runner stops immediately on disabled/auth errors:

   ```sh
   node solver/run_hosted_capacity_measurements.mjs --run --smoke \
     --cases case-07-infeasible --url https://STAGING-APP-ORIGIN \
     --output /absolute/path/to/new-smoke-results
   ```
8. From a fixed client location, run the seven cases, one request at a time:

   ```sh
   node solver/run_hosted_capacity_measurements.mjs --run \
     --url https://STAGING-APP-ORIGIN \
     --output /absolute/path/to/new-results --samples 10
   ```

   Set `WAB_CAPACITY_TEST_TOKEN` in the caller's environment. Do not put it on the
   command line. Record commit, resources, database version/tier/region, client
   location, time, instance count and any platform timeout. Take a separately
   labelled first-request-after-deployment/inactivity sample with `--first-request`; this runner's
   first request is saved as a warm-up and is not an OS-cold measurement. Do not
   restart services automatically or simulate cold hosting by guessing a delay.
9. Revalidate the saved arrangements and compare with the existing proven net
   offers. Separate calculation-only, backend round-trip, app handler and complete
   external request latency. Complete request includes the actual HTTPS path to
   the staging app and its internal service/database transport. Timeouts,
   unproved results and failures remain exceptions, never successful optima.
10. Disable the flag after the test. The operational workflow has never switched.

The frozen fixtures replace live flight-data reads and baggage preparation.
Even after deployment, these measurements establish the **hosted fixed-input
comparison**, not the production traffic-plan workflow or legacy SQL turnaround.
A genuine live end-to-end replacement needs a separately reviewed input adapter
and operational cutover; neither is enabled by this package.

## Rollback

Set `WAB_CAPACITY_TESTS_ENABLED=false` and redeploy/restart the app component so
it reads the new environment. The endpoint returns 404. Stop the private capacity
service and revoke test tokens if retiring it. Restore the recorded staging app
spec/deployment if needed. The normal calculation and saved flight plans have no
new dependency on either service and require no data rollback. Do not delete an
existing/shared database as part of rollback.

## Verification and remaining deployment checks

Prepared unit tests cover route feature gates, tokens, allowed cases, bounded
bodies, stale/malformed witnesses, unproved statuses, admission and backend URL
restrictions; Python tests cover sealed inputs, read-only connection options,
child timings and error redaction. Next's production build checks the route.

This workstation has no Docker or DigitalOcean CLI installed, and no staging
app ID/spec or database URL has been supplied. Therefore **container builds,
native PostgreSQL connectivity/grants, App Platform spec validation, healthcheck
and hosted smoke/latency tests remain unexecuted**. Do not describe this as a
verified or deployed hosting environment. No new hosted timing claims are made.

References checked for this preparation:

- [DigitalOcean internal routing](https://docs.digitalocean.com/products/app-platform/how-to/manage-internal-routing/)
- [App specification](https://docs.digitalocean.com/products/app-platform/reference/app-spec/)
- [Dockerfile builds](https://docs.digitalocean.com/products/app-platform/reference/dockerfile/)
- [Runtime/bindable variables](https://docs.digitalocean.com/products/app-platform/how-to/use-environment-variables/)
- [Psycopg connection options](https://www.psycopg.org/psycopg3/docs/api/connections.html)

Local preparation checks completed on 23 October 2026: 933 TypeScript tests,
20 Python tests, TypeScript checking, changed-file lint and the production Next.js
build passed. The new route is present in the build and remains disabled by
default. Original sealed scenario inputs still reproduce unchanged. These checks
do not substitute for the unexecuted container/native-database/provider checks.
