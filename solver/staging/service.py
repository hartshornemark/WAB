"""Staging-only, authenticated fixed-case service. Never serves the live workflow."""
import hashlib
import hmac
import json
import importlib.metadata
import os
from pathlib import Path
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / 'verification/a350-v2-seven-scenarios-2026-10-23/final'
MAX_BODY = 256_000
ADMISSION = threading.BoundedSemaphore(1)


def registry(root=FIXTURES):
    rows = json.loads((root / 'results.json').read_text())['rows']
    cases = {}
    for row in rows:
        raw = (root / 'inputs' / (row['id'] + '.json')).read_bytes()
        if row['outcome'] != 'EQUIVALENT' or hashlib.sha256(raw).hexdigest() != row['inputSha256']:
            raise ValueError('Fixture integrity failure')
        cases[row['id']] = (row['inputSha256'], json.loads(raw))
    if len(cases) != 7:
        raise ValueError('Seven verified cases are required')
    return cases


def check_request(body, cases):
    if not isinstance(body, dict) or set(body) != {'caseId', 'engine', 'inputSha256', 'problem'}:
        raise ValueError('Invalid request')
    case = cases.get(body['caseId'])
    if body['engine'] not in ('DATABASE', 'SOLVER') or case is None or body['inputSha256'] != case[0] or json.dumps(body['problem'], sort_keys=True) != json.dumps(case[1], sort_keys=True):
        raise ValueError('Only the verified fixed A350 cases are accepted')
    return case[1]


def run_solver(problem):
    started = time.perf_counter_ns()
    child = subprocess.Popen([sys.executable, str(ROOT / 'staging/worker.py')], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                             text=True, env={'PATH': os.environ.get('PATH', ''), 'PYTHONUNBUFFERED': '1'})
    try:
        stdout, _ = child.communicate(json.dumps(problem), timeout=12)
    except subprocess.TimeoutExpired:
        child.kill(); child.communicate()
        raise RuntimeError('Solver execution limit; no maximum confirmed') from None
    if child.returncode or len(stdout) > 1_000_000:
        raise RuntimeError('Solver unavailable')
    lines = [json.loads(line) for line in stdout.splitlines()]
    if len(lines) != 2:
        raise RuntimeError('Invalid solver protocol')
    return {**lines[1], 'workerStartupMilliseconds': (lines[0]['readyAtNanoseconds'] - started) / 1_000_000}


def connect_database():
    import psycopg  # Loaded only when configured, never in the model worker.
    return psycopg.connect(os.environ['CAPACITY_DATABASE_URL'], autocommit=True, connect_timeout=5,
                           options='-c default_transaction_read_only=on -c statement_timeout=60000 -c lock_timeout=1000')


def database_ready():
    with connect_database() as conn:
        row = conn.execute("select current_setting('transaction_read_only'),current_setting('server_version'),r.rolsuper,r.rolcreatedb,r.rolcreaterole,current_database(),to_regprocedure('capacity_reference.timed_offer(jsonb)') is not null,pg_has_role(current_user,(select datdba from pg_database where datname=current_database()),'MEMBER') from pg_roles r where r.rolname=current_user").fetchone()
        if not row or row[0] != 'on' or any(row[2:5]) or row[5] != os.environ.get('CAPACITY_DATABASE_NAME') or not row[6] or row[7]:
            raise RuntimeError('Restricted read-only reference database is not ready')
        return row[1]


def run_database(problem):
    with connect_database() as conn:
        return conn.execute('select capacity_reference.timed_offer(%s::jsonb)', (json.dumps(problem),)).fetchone()[0]


def make_handler(cases, secret, deployment):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass  # Never log authorization headers, database URLs or request bodies.

        def reply(self, status, body):
            raw = json.dumps(body).encode()
            self.send_response(status)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Content-Length', str(len(raw)))
            self.end_headers(); self.wfile.write(raw)

        def do_GET(self):
            if self.path != '/healthz':
                return self.reply(404, {'error': 'Not found'})
            try:
                version = database_ready()
                self.reply(200, {'ready': True, 'rulesVersion': 'A350_MAX_NET_CARGO_V2', 'postgresVersion': version, **deployment})
            except Exception:
                self.reply(503, {'ready': False})

        def do_POST(self):
            auth = self.headers.get('Authorization', '')
            if len(auth) > 512 or not hmac.compare_digest(auth.encode(), ('Bearer ' + secret).encode()):
                return self.reply(401, {'error': 'Authentication required'})
            if self.path != '/v1/capacity':
                return self.reply(404, {'error': 'Not found'})
            if not ADMISSION.acquire(blocking=False):
                return self.reply(429, {'error': 'Capacity test is busy'})
            try:
                length = int(self.headers.get('Content-Length', '0'))
                if not 0 < length <= MAX_BODY or self.headers.get_content_type() != 'application/json':
                    return self.reply(400, {'error': 'Invalid body'})
                self.connection.settimeout(5)
                body = json.loads(self.rfile.read(length))
                problem = check_request(body, cases)
                started = time.perf_counter_ns()
                measured = run_solver(problem) if body['engine'] == 'SOLVER' else run_database(problem)
                self.reply(200, {**measured, 'engine': body['engine'], 'inputSha256': body['inputSha256'],
                                 'backendHandlerMilliseconds': (time.perf_counter_ns() - started) / 1_000_000,
                                 'deployment': deployment})
            except (ValueError, KeyError, TypeError):
                self.reply(400, {'error': 'Invalid fixed-case request'})
            except Exception:
                self.reply(503, {'error': 'Calculation unavailable; no maximum confirmed'})
            finally:
                ADMISSION.release()
    return Handler


if __name__ == '__main__':
    secret = os.environ.get('CAPACITY_SERVICE_TOKEN', '')
    if os.environ.get('WAB_DEPLOYMENT_ENV') != 'staging' or len(secret) < 32 or not os.environ.get('CAPACITY_DATABASE_URL') or os.environ.get('CAPACITY_DATABASE_NAME') != 'capacity_staging_reference':
        raise RuntimeError('Explicit staging configuration and backend/database secrets are required')
    cases = registry()
    postgres_version = database_ready()  # Fail deployment readiness if native SQL/permissions are missing.
    deployment = {'revision': os.environ.get('CAPACITY_RELEASE_ID', 'unlabelled'), 'databaseEngine': 'native PostgreSQL', 'workerMode': 'one-shot', 'concurrency': 1,
                  'postgresVersion': postgres_version, 'pythonVersion': sys.version.split()[0], 'ortoolsVersion': importlib.metadata.version('ortools'),
                  'modelSha256': hashlib.sha256((ROOT / 'cargo_capacity.py').read_bytes()).hexdigest(),
                  'referenceSha256': hashlib.sha256((ROOT / 'reference/max_net_cargo_v2.sql').read_bytes() + (ROOT / 'reference/frontier_net_cargo_v2.sql').read_bytes()).hexdigest()}
    server = ThreadingHTTPServer(('0.0.0.0', int(os.environ.get('PORT', '8080'))), make_handler(cases, secret, deployment))
    server.daemon_threads = True
    server.serve_forever()
