/** Summarise completed recorded requests; never execute a calculation. */
import { readFileSync, writeFileSync, mkdirSync, readdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { summariseMeasurement } from './cargo_capacity_statistics.mjs';
const repo = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const root = resolve(process.argv[2] ?? '');
if (!process.argv[2]) throw Error('Pass the completed measurement directory.');
const read = file => JSON.parse(readFileSync(file, 'utf8'));
const save = (file, value) => writeFileSync(file, JSON.stringify(value, null, 2) + '\n');
const sha = value => createHash('sha256').update(value).digest('hex');
const report = read(root + '/results.json');
if (!report.finishedAt) throw Error('Measurements are not complete.');
const summary = summariseMeasurement(report);
const cases = [...new Set(report.rows.map(r => r.caseId))];
const expected = cases.length * 2 * (report.repetitions.coldPerCase + report.repetitions.warmPerCase + 1);
if (report.rows.length !== expected) throw Error('Missing recorded requests.');
const complete = summary.summary.every(r => r.recorded === r.requested && r.verified === r.requested) && summary.failures.length === 0;
summary.completeWithoutFailures = complete;
summary.measuredRequests = report.rows.filter(r => r.phase !== 'warmup').length;
summary.totalRequestsIncludingWarmups = report.rows.length;
summary.analysisCodeSha256 = Object.fromEntries(['solver/cargo_capacity_statistics.mjs','solver/report_cargo_capacity_measurement.mjs'].map(p => [p,sha(readFileSync(repo + '/' + p))]));
save(root + '/summary.json', summary);
const group = (id, engine, phase) => summary.summary.find(r => r.caseId === id && r.engine === engine && r.phase === phase);
const fmt = n => n === null ? '—' : n < 1 ? '<1 ms' : n < 1000 ? `${n.toFixed(1)} ms` : `${(n / 1000).toFixed(3)} s`;
const table = phase => cases.map(id => {
 const d = group(id,'database',phase), s = group(id,'solver',phase);
 const m = (r,key,p='median') => fmt(r.metrics[key][p]);
 return `| ${id.replace('case-','')} | ${m(d,'calculationMilliseconds')} | ${m(s,'calculationMilliseconds')} | ${m(d,'completeRequestMilliseconds')} / ${m(d,'completeRequestMilliseconds','p95')} | ${m(s,'completeRequestMilliseconds')} / ${m(s,'completeRequestMilliseconds','p95')} | ${d.verified}/${d.requested}; ${s.verified}/${s.requested} |`;
}).join('\n');
const header = '| Case | DB calculation median | Solver calculation median | DB complete request median / p95 | Solver complete request median / p95 | Verified DB; solver |\n| --- | ---: | ---: | ---: | ---: | --- |\n';
const readme = `# Repeated local calculation and request measurements

${complete ? '**Completed without failures or unproved/mismatched results.**' : '**Completed with exceptions; inspect the failure records before drawing conclusions.**'}

This compares the aligned V2 SQL reference in **local PGlite** with the same V2
CP-SAT model in a **local one-shot Python worker**. It does not measure native
hosted PostgreSQL/Supabase, the live legacy database function, a remote solver,
or the production flight workflow.

Recorded ${summary.measuredRequests} measured requests across ${cases.length} scenarios, plus
${summary.warmupsExcluded} separately recorded and excluded warm-ups. Every request
was executed serially. Engine order alternated by repetition. No outliers were
removed. Each successful response matched the sealed Step 3 result and passed
the server's independent resource/witness validator.

## Warm requests

${report.repetitions.warmPerCase} measured requests per engine/case after one validated warm-up. The
HTTP/API and database session are reused. Python still starts a fresh process
for every solver request, matching the one-shot lifecycle of the current adapter.

${header}${table('warm')}

## Fresh-session requests

${report.repetitions.coldPerCase} requests per engine/case, each to a fresh measurement service and,
for SQL, a newly initialized PGlite instance. This is not an OS-cache-cold test.

${header}${table('cold')}

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

Solver search limit: ${report.budgets.pythonSearchSeconds} seconds; process deadline:
${report.budgets.pythonHardSeconds} seconds. SQL statement limit: ${report.budgets.sqlStatementSeconds}
seconds, plus the external ${report.budgets.requestHardSeconds}-second request deadline that can
terminate the isolated service. Startup is separately bounded at
${report.budgets.serviceStartupHardSeconds} seconds. Limits are ceilings, not measured durations.

Errors, FEASIBLE/UNKNOWN responses and mismatches remain visible in raw records
and summary.json; their timings are not represented as successful optimum
latencies. Count of exceptional responses, including warm-ups: ${summary.failures.length}.
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

\`\`\`sh
node --import tsx solver/measure_cargo_capacity.mjs --run \\
  --output /absolute/path/to/new-measurement-directory \\
  --python /absolute/path/to/python-with-ortools --samples 10 --cold 3
node solver/report_cargo_capacity_measurement.mjs /absolute/path/to/new-measurement-directory
\`\`\`

The report command only processes recorded data and never reruns calculations.
`;
writeFileSync(root + '/README.md', readme);
for (const [file, expectedHash] of Object.entries({ ...report.codeSha256, ...summary.analysisCodeSha256 })) {
 const raw = readFileSync(repo + '/' + file);
 if (sha(raw) !== expectedHash) throw Error(`Source changed since measurement: ${file}`);
 const dest = root + '/code/' + file; mkdirSync(dirname(dest),{recursive:true}); writeFileSync(dest,raw);
}
function files(dir) { return readdirSync(dir,{withFileTypes:true}).flatMap(e=>e.isDirectory()?files(dir+'/'+e.name):[dir+'/'+e.name]); }
writeFileSync(root + '/SHA256SUMS', files(root).filter(p=>!p.endsWith('/SHA256SUMS')).sort().map(p=>`${sha(readFileSync(p))}  ${p.slice(root.length+1)}`).join('\n')+'\n');
console.log(`Summarised ${summary.measuredRequests} measured requests; ${summary.failures.length} exceptions.`);
