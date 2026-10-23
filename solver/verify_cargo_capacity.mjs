/** Opt-in seven-scenario correctness comparison. No shared database access. */
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { spawn, execFileSync } from 'node:child_process';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { PGlite } from '@electric-sql/pglite';
import { validateCargoCapacityProblem, validateCargoCapacityResult } from '../src/domain/cargo-capacity.ts';

const repo = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const sha = value => createHash('sha256').update(value).digest('hex');
const save = (path, value) => writeFileSync(path, JSON.stringify(value, null, 2) + '\n');
const { values } = parseArgs({ options: {
  run: { type: 'boolean' }, output: { type: 'string' }, python: { type: 'string' },
  'solver-seconds': { type: 'string', default: '2' }, 'database-seconds': { type: 'string', default: '60' },
  cases: { type: 'string' }, 'database-child': { type: 'string' },
} });
const databaseSeconds = Number(values['database-seconds']);
if (!Number.isInteger(databaseSeconds) || databaseSeconds < 1 || databaseSeconds > 120) throw Error('Database statement budget must be 1–120 seconds.');

if (values['database-child']) {
  const p = validateCargoCapacityProblem(JSON.parse(readFileSync(values['database-child'], 'utf8')));
  const db = new PGlite();
  try {
    for (const file of ['max_net_cargo_v2.sql', 'frontier_net_cargo_v2.sql']) await db.exec(readFileSync(repo + '/solver/reference/' + file, 'utf8'));
    await db.exec(`set statement_timeout='${databaseSeconds}s'`);
    const result = (await db.query('select capacity_reference.max_net_cargo_v2($1::jsonb) result', [JSON.stringify(p)])).rows[0].result;
    process.stdout.write(JSON.stringify({ result }));
  } catch (e) { process.stdout.write(JSON.stringify({ error: { message: e.message, code: e.code } })); }
  finally { await db.close(); }
} else {
  if (!values.run || !values.output || !values.python) throw Error('Explicit --run --output <new-directory> --python <runtime> required. Use node --import tsx.');
  const solverSeconds = Number(values['solver-seconds']);
  if (!(solverSeconds > 0 && solverSeconds <= 10)) throw Error('Solver budget must be >0 and <=10 seconds.');
  const root = repo + '/tests/fixtures/cargo-capacity/passenger-scenarios-v2';
  const manifest = JSON.parse(readFileSync(root + '/manifest.json', 'utf8'));
  for (const [path, expected] of Object.entries(manifest.sourceSha256)) if (sha(readFileSync(resolve(root, path))) !== expected) throw Error(`Source checksum changed: ${path}`);
  const selected = values.cases?.split(',') ?? manifest.cases.map(c => c.id);
  if (selected.some(id => !manifest.cases.some(c => c.id === id))) throw Error('Unknown case.');
  const output = resolve(values.output);
  if (output.startsWith(root)) throw Error('Never overwrite frozen fixtures.');
  mkdirSync(output); // Fail if an existing attempt would be overwritten.
  mkdirSync(output + '/inputs');
  const report = { schemaVersion: 1, startedAt: new Date().toISOString(), rulesVersion: manifest.rulesVersion,
    scope: 'Offline correctness comparison, one execution per engine/case. Not a performance benchmark or live legacy database comparison.',
    codeCommit: execFileSync('git', ['rev-parse', 'HEAD'], { cwd: repo, encoding: 'utf8' }).trim(),
    codeSha256: Object.fromEntries(['solver/verify_cargo_capacity.mjs', 'solver/cargo_capacity.py', 'solver/cp_sat_solver.py', 'solver/reference/max_net_cargo_v2.sql', 'solver/reference/frontier_net_cargo_v2.sql', 'src/domain/cargo-capacity.ts'].map(p => [p, sha(readFileSync(repo + '/' + p))])),
    manifestSha256: sha(readFileSync(root + '/manifest.json')), nodeVersion: process.version,
    pythonRuntime: JSON.parse(execFileSync(values.python, ['-c', 'import sys,ortools,json; print(json.dumps({"python":sys.version,"ortools":ortools.__version__}))'], {encoding:'utf8'})),
    budgets: { solverSeconds, solverHardSeconds: solverSeconds + 2, databaseStatementSeconds: databaseSeconds, databaseHardSeconds: databaseSeconds + 5, databaseStateLimit: 20000 }, rows: [] };
  const launch = (exe, args, input, seconds) => new Promise(resolveChild => {
    const child = spawn(exe, args, { cwd: repo, env: { PATH: process.env.PATH, PYTHONUNBUFFERED: '1' }, stdio: ['pipe', 'pipe', 'pipe'] });
    let stdout = '', stderr = '', expired = false, excessive = false;
    const timer = setTimeout(() => { expired = true; child.kill('SIGKILL'); }, seconds * 1000);
    const receive = target => data => {
      if (target === 'stdout') stdout += data; else stderr += data;
      if (stdout.length + stderr.length > 2_000_000) { excessive = true; child.kill('SIGKILL'); }
    };
    child.stdout.on('data', receive('stdout')); child.stderr.on('data', receive('stderr'));
    child.on('error', e => { clearTimeout(timer); resolveChild({ error: { message: e.message } }); });
    child.stdin.on('error', () => {});
    child.on('close', code => {
      clearTimeout(timer);
      if (expired || excessive) return resolveChild({ error: { code: expired ? 'HARD_TIMEOUT' : 'OUTPUT_LIMIT', message: 'No optimum established.' } });
      if (code !== 0) return resolveChild({ error: { code, message: stderr } });
      try { resolveChild(JSON.parse(stdout)); } catch { resolveChild({ error: { message: 'Unreadable worker output', stdout, stderr } }); }
    });
    child.stdin.end(input);
  });
  for (const c of manifest.cases.filter(c => selected.includes(c.id))) {
    const original = readFileSync(root + '/' + c.solverInput, 'utf8');
    if (sha(original) !== c.inputSha256 || c.solverInput !== c.databaseInput) throw Error('Component input mismatch.');
    const p = JSON.parse(original);
    if (solverSeconds !== p.timeLimitSeconds) {
      p.timeLimitSeconds = solverSeconds;
      p.inputRevision = 'sha256:' + sha(JSON.stringify({ ...p, inputRevision: undefined }));
    }
    validateCargoCapacityProblem(p);
    const raw = JSON.stringify(p, null, 2) + '\n', path = output + '/inputs/' + c.id + '.json';
    writeFileSync(path, raw);
    const [database, solverOutput] = await Promise.all([
      launch(process.execPath, ['--import', repo + '/node_modules/tsx/dist/loader.mjs', fileURLToPath(import.meta.url), '--database-child', path, '--database-seconds', String(databaseSeconds)], undefined, databaseSeconds + 5),
      launch(values.python, [repo + '/solver/cp_sat_solver.py'], raw, solverSeconds + 2),
    ]);
    const solver = solverOutput.error ? solverOutput : { result: solverOutput };
    for (const engine of [database, solver]) if (engine.result) {
      try {
        // SQL witnesses use the same independent resource validator. The raw SQL
        // result retains its own metadata; this adapter does not relabel the report.
        validateCargoCapacityResult(p, { ...engine.result, engine: 'OR-TOOLS CP-SAT', solveMilliseconds: engine.result.solveMilliseconds ?? 0 });
        engine.validation = 'PASS';
        if (engine.result.arrangement) {
          const a = engine.result.arrangement;
          engine.counts = { pallets: a.cargoUlds.filter(r => p.positions.find(pos => pos.id === r.positionId).kind === 'PALLET').length,
            containers: a.cargoUlds.filter(r => p.positions.find(pos => pos.id === r.positionId).kind === 'CONTAINER').length,
            baggageUlds: a.baggageUlds.length };
        }
      } catch (e) { engine.validation = 'FAIL'; engine.validationError = e.message; }
    }
    const proven = [database, solver].every(e => e.validation === 'PASS' && ['OPTIMAL', 'INFEASIBLE'].includes(e.result.status));
    const equal = proven && database.result.status === solver.result.status && (database.result.arrangement?.cargoNetWeightGrams ?? null) === (solver.result.arrangement?.cargoNetWeightGrams ?? null);
    const row = { id: c.id, originalInputSha256: c.inputSha256, inputSha256: sha(raw), inputRevision: p.inputRevision,
      budgetOnlyChange: solverSeconds !== JSON.parse(original).timeLimitSeconds,
      baggageReservationHash: sha(JSON.stringify(p.baggageUlds)), fixedReservationHash: sha(JSON.stringify(p.fixedLoads)),
      database, solver, outcome: proven ? equal ? 'EQUIVALENT' : 'MISMATCH' : 'INCONCLUSIVE' };
    report.rows.push(row); save(output + '/' + c.id + '.json', row); save(output + '/results.json', report);
    console.log(c.id, row.outcome, database.result?.status ?? database.error, solver.result?.status ?? solver.error);
  }
  report.finishedAt = new Date().toISOString(); save(output + '/results.json', report);
}
