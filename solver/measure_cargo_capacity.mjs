/** Opt-in, serial local request benchmark. No shared database or production route. */
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { spawn, execFileSync } from 'node:child_process';
import { createServer, request, Agent } from 'node:http';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { performance } from 'node:perf_hooks';
import { cpus, platform, release, arch, totalmem } from 'node:os';
import { PGlite } from '@electric-sql/pglite';
import { validateCargoCapacityProblem, validateCargoCapacityResult } from '../src/domain/cargo-capacity.ts';

const repo = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const sha = data => createHash('sha256').update(data).digest('hex');
const save = (path, data) => writeFileSync(path, JSON.stringify(data, null, 2) + '\n');
const { values } = parseArgs({ options: {
  run: { type: 'boolean' }, output: { type: 'string' }, python: { type: 'string' },
  samples: { type: 'string', default: '10' }, cold: { type: 'string', default: '3' },
  'service-engine': { type: 'string' }, 'input': { type: 'string' }, 'cases': { type: 'string' },
} });

function launchPython(python, raw) {
  return new Promise((resolveWorker, reject) => {
    const started = performance.now();
    const child = spawn(python, [repo + '/solver/measure_cargo_worker.py'], { cwd: repo, env: { PATH: process.env.PATH, PYTHONUNBUFFERED: '1' }, stdio: ['pipe', 'pipe', 'pipe'] });
    let stdout = '', stderr = '', startup = null, excessive = false;
    const limit = setTimeout(() => { child.kill('SIGKILL'); }, 12000);
    child.stdout.on('data', data => {
      stdout += data;
      if (startup === null && stdout.includes('\n')) startup = performance.now() - started;
      if (stdout.length > 2_000_000) { excessive = true; child.kill('SIGKILL'); }
    });
    child.stderr.on('data', data => { stderr += data; if (stderr.length > 1_000_000) { excessive = true; child.kill('SIGKILL'); } });
    child.on('error', error => { clearTimeout(limit); reject(error); });
    child.stdin.on('error', () => {});
    child.on('close', code => {
      clearTimeout(limit);
      if (code !== 0 || excessive) return reject(new Error(`Worker failed or exceeded its limit: ${stderr}`));
      try {
        const lines = stdout.trim().split('\n').map(line => JSON.parse(line));
        if (lines.length !== 2 || lines[0].ready !== true || startup === null) throw Error('Invalid measurement protocol.');
        resolveWorker({ ...lines[1], workerStartupMilliseconds: startup, workerRoundTripMilliseconds: performance.now() - started });
      } catch (error) { reject(error); }
    });
    child.stdin.end(raw);
  });
}

if (values['service-engine']) {
  const engine = values['service-engine'];
  if (!['database', 'solver'].includes(engine) || !values.input || !values.python) throw Error('Invalid isolated service configuration.');
  const db = engine === 'database' ? new PGlite() : null;
  if (db) {
    for (const name of ['max_net_cargo_v2.sql', 'frontier_net_cargo_v2.sql']) await db.exec(readFileSync(repo + '/solver/reference/' + name, 'utf8'));
    await db.exec("set statement_timeout='60s'");
    await db.exec(`create function capacity_reference.timed_offer(p jsonb) returns jsonb language plpgsql as $$
      declare started timestamptz; result jsonb; elapsed numeric;
      begin
       started:=clock_timestamp(); result:=capacity_reference.max_net_cargo_v2(p);
       elapsed:=extract(epoch from clock_timestamp()-started)*1000;
       return jsonb_build_object('result',result,'calculationMilliseconds',elapsed);
      end $$;`);
  }
  let busy = false;
  const server = createServer(async (req, res) => {
    const started = performance.now();
    if (busy) { res.writeHead(503); res.end('busy'); return; }
    busy = true;
    try {
      if (req.method !== 'POST' || req.url !== '/capacity') throw Error('Unsupported measurement request.');
      let body = '';
      for await (const chunk of req) { body += chunk; if (body.length > 1000) throw Error('Oversized request.'); }
      const { inputSha256 } = JSON.parse(body);
      const loadStarted = performance.now();
      const raw = readFileSync(values.input, 'utf8');
      if (sha(raw) !== inputSha256) throw Error('Input hash mismatch.');
      const p = validateCargoCapacityProblem(JSON.parse(raw));
      const inputMilliseconds = performance.now() - loadStarted;
      const backendStarted = performance.now();
      const measured = db ? (await db.query('select capacity_reference.timed_offer($1::jsonb) measured', [JSON.stringify(p)])).rows[0].measured : await launchPython(values.python, raw);
      const backendMilliseconds = performance.now() - backendStarted;
      const validationStarted = performance.now();
      validateCargoCapacityResult(p, { ...measured.result, engine: 'OR-TOOLS CP-SAT', solveMilliseconds: measured.result.solveMilliseconds ?? 0 });
      const validationMilliseconds = performance.now() - validationStarted;
      res.setHeader('Content-Type', 'application/json');
      res.end(JSON.stringify({ ...measured, inputMilliseconds, backendMilliseconds, validationMilliseconds, serverHandlerMilliseconds: performance.now() - started, inputSha256, validation: 'PASS' }));
    } catch (error) {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: { message: error.message, code: error.code }, serverHandlerMilliseconds: performance.now() - started }));
    } finally { busy = false; }
  });
  await new Promise(resolveReady => server.listen(0, '127.0.0.1', resolveReady));
  process.stdout.write(JSON.stringify({ port: server.address().port }) + '\n');
} else {
  const samples = Number(values.samples), cold = Number(values.cold);
  if (!values.run || !values.output || !values.python || !Number.isInteger(samples) || samples < 2 || samples > 50 || !Number.isInteger(cold) || cold < 2 || cold > 10) throw Error('Use --run --output <new-directory> --python <runtime>; 2–50 warm and 2–10 cold samples.');
  const inputRoot = repo + '/solver/verification/a350-v2-seven-scenarios-2026-10-23';
  const verified = JSON.parse(readFileSync(inputRoot + '/final/results.json', 'utf8'));
  const selected = values.cases?.split(',') ?? verified.rows.map(r => r.id);
  if (selected.some(id => !verified.rows.some(r => r.id === id))) throw Error('Unknown scenario.');
  const output = resolve(values.output);
  if (output.startsWith(inputRoot) || output.startsWith(repo + '/tests/fixtures/')) throw Error('Do not overwrite sealed inputs/evidence.');
  mkdirSync(output); mkdirSync(output + '/inputs');
  const report = { schemaVersion: 1, startedAt: new Date().toISOString(), scope: 'Serial loopback HTTP benchmark: aligned V2 SQL in local PGlite versus one-shot local Python CP-SAT. Not live PostgreSQL/Supabase, remote solver transport, or the production flight API.',
    timingBoundaries: { calculation: 'Full capacity function call only; excludes process/module startup and IPC/HTTP. Python monotonic high-resolution timer; SQL clock_timestamp wrapper.',
      completeRequest: 'Client monotonic timer before request JSON encoding through HTTP response receipt, parsing and expected-result check. Includes server file input loading, input validation, engine invocation, Python startup/IPC, independent result validation and loopback HTTP transport.',
      serviceStartup: 'Fresh measurement service launch through ready HTTP listener, recorded separately; database initialization/schema installation are not charged to HTTP request time.',
      cold: 'First request to a fresh API process and (for SQL) newly initialized PGlite instance; not OS-cache-cold.',
      warm: 'One validated warm-up then repeated requests to the same API/database session. Solver still launches a fresh Python worker per request, matching the existing one-shot adapter.',
      excluded: 'Live database reads, authentication, production baggage preparation, WAN transport, external service hosting, UI/browser and deployment-wide concurrency.' },
    repetitions: { warmPerCase: samples, coldPerCase: cold, unmeasuredWarmupsPerCase: 1 }, budgets: { pythonSearchSeconds: 10, pythonHardSeconds: 12, sqlStatementSeconds: 60, requestHardSeconds: 65, serviceStartupHardSeconds: 20 },
    sourceCommit: execFileSync('git', ['rev-parse', 'HEAD'], { cwd: repo, encoding: 'utf8' }).trim(),
    machine: { platform: platform(), release: release(), architecture: arch(), cpu: cpus()[0]?.model, logicalCpus: cpus().length, memoryBytes: totalmem() },
    pgliteVersion: JSON.parse(readFileSync(repo + '/node_modules/@electric-sql/pglite/package.json', 'utf8')).version,
    nodeVersion: process.version, runtime: JSON.parse(execFileSync(values.python, ['-c', 'import sys,ortools,json; print(json.dumps({"python":sys.version,"ortools":ortools.__version__}))'], { encoding: 'utf8' })),
    codeSha256: Object.fromEntries(['solver/measure_cargo_capacity.mjs','solver/measure_cargo_worker.py','solver/cargo_capacity.py','solver/reference/max_net_cargo_v2.sql','solver/reference/frontier_net_cargo_v2.sql','src/domain/cargo-capacity.ts'].map(p => [p, sha(readFileSync(repo + '/' + p))])), rows: [] };
  save(output + '/results.json', report);
  function startService(engine, input) {
    return new Promise((resolveService, reject) => {
      const started = performance.now();
      const child = spawn(process.execPath, ['--import', repo + '/node_modules/tsx/dist/loader.mjs', fileURLToPath(import.meta.url), '--service-engine', engine, '--input', input, '--python', values.python], { cwd: repo, env: { PATH: process.env.PATH }, stdio: ['ignore', 'pipe', 'pipe'] });
      let stdout = '', stderr = '', ready = false;
      const timer = setTimeout(() => { child.kill('SIGKILL'); reject(Error('Service startup timed out.')); }, 20000);
      child.stderr.on('data', x => { stderr += x; if (stderr.length > 1_000_000) child.kill('SIGKILL'); });
      child.stdout.on('data', x => {
        stdout += x;
        if (!ready && stdout.includes('\n')) {
          ready = true; clearTimeout(timer);
          try { resolveService({ child, port: JSON.parse(stdout.trim()).port, serviceStartupMilliseconds: performance.now() - started }); }
          catch (e) { child.kill('SIGKILL'); reject(e); }
        }
      });
      child.on('error', e => { clearTimeout(timer); reject(e); });
      child.on('close', code => { clearTimeout(timer); if (!ready) reject(Error(`Service exited before ready (${code}): ${stderr}`)); });
    });
  }
  async function stopService(service) {
    await new Promise(resolveStop => { if (service.child.exitCode !== null || service.child.signalCode !== null) return resolveStop(); service.child.once('close', resolveStop); service.child.kill('SIGKILL'); });
  }
  function measureRequest(service, hash, expected, agent) {
    return new Promise(resolveRequest => {
      const started = performance.now(), body = JSON.stringify({ inputSha256: hash });
      const req = request({ host: '127.0.0.1', port: service.port, path: '/capacity', method: 'POST', agent, headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) } }, res => {
        let raw = '';
        res.on('data', x => { raw += x; if (raw.length > 2_000_000) req.destroy(Error('Response too large.')); });
        res.on('end', () => {
          clearTimeout(timer);
          try {
            const measured = JSON.parse(raw);
            if (res.statusCode !== 200 || measured.error) return resolveRequest({ ...measured, outcome: 'ERROR', completeRequestMilliseconds: performance.now() - started });
            const equal = measured.validation === 'PASS' && measured.inputSha256 === hash && measured.result.status === expected.status && (measured.result.arrangement?.cargoNetWeightGrams ?? null) === (expected.arrangement?.cargoNetWeightGrams ?? null);
            resolveRequest({ ...measured, completeRequestMilliseconds: performance.now() - started, outcome: equal ? 'VERIFIED' : ['UNKNOWN','FEASIBLE'].includes(measured.result.status) ? 'INCONCLUSIVE' : 'MISMATCH' });
          } catch (error) { resolveRequest({ error: { message: error.message }, outcome: 'ERROR', completeRequestMilliseconds: performance.now() - started }); }
        });
      });
      const timer = setTimeout(() => req.destroy(Error('Request hard deadline exceeded.')), 65000);
      req.on('error', error => { clearTimeout(timer); resolveRequest({ error: { message: error.message }, outcome: 'ERROR', completeRequestMilliseconds: performance.now() - started }); });
      req.end(body);
    });
  }
  const sessions = new Map(), agents = new Map();
  process.once('exit', () => { for (const service of sessions.values()) service.child.kill('SIGKILL'); });
  for (const c of verified.rows.filter(c => selected.includes(c.id))) {
    const raw = readFileSync(inputRoot + '/final/inputs/' + c.id + '.json', 'utf8');
    if (sha(raw) !== c.inputSha256) throw Error('Verified input checksum mismatch.');
    const input = output + '/inputs/' + c.id + '.json'; writeFileSync(input, raw);
    for (let i = 0; i < cold + samples + 1; i++) {
      const phase = i < cold ? 'cold' : i === cold ? 'warmup' : 'warm';
      // Alternate engine order by repetition to reduce consistent order bias.
      for (const engine of i % 2 ? ['solver','database'] : ['database','solver']) {
        const key = c.id + ':' + engine;
        let service = sessions.get(key), agent = agents.get(key);
        const sessionReused = Boolean(service);
        try {
          if (!service) { service = await startService(engine, input); sessions.set(key, service); agent = new Agent({ keepAlive: true, maxSockets: 1 }); agents.set(key, agent); }
          const measured = await measureRequest(service, c.inputSha256, c.solver.result, agent);
          report.rows.push({ caseId: c.id, engine, phase, sessionReused, repetition: phase === 'cold' ? i + 1 : phase === 'warmup' ? 0 : i - cold, inputSha256: c.inputSha256, serviceStartupMilliseconds: service.serviceStartupMilliseconds, ...measured });
          if (phase === 'cold' || measured.outcome === 'ERROR') { await stopService(service); sessions.delete(key); agent.destroy(); agents.delete(key); }
        } catch (error) {
          report.rows.push({ caseId: c.id, engine, phase, repetition: i, inputSha256: c.inputSha256, outcome: 'ERROR', error: { message: error.message } });
          if (service) await stopService(service); sessions.delete(key); agent?.destroy(); agents.delete(key);
        }
        save(output + '/results.json', report);
        const last = report.rows.at(-1);
        console.log(c.id,engine,phase,last.repetition,last.outcome,last.calculationMilliseconds?.toFixed(2),last.completeRequestMilliseconds?.toFixed(2));
      }
    }
    for (const engine of ['database','solver']) { const key = c.id + ':' + engine; if (sessions.has(key)) await stopService(sessions.get(key)); agents.get(key)?.destroy(); sessions.delete(key); agents.delete(key); }
  }
  report.finishedAt = new Date().toISOString(); save(output + '/results.json', report);
}
