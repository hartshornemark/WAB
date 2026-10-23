"""One-shot fixed-fixture benchmark worker inside the existing app container.

No listening socket or operational flight access. DATABASE receives only its
restricted PostgreSQL connection; SOLVER receives no database credentials.
"""
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import ssl
import sys
import time
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / 'verification/a350-v2-seven-scenarios-2026-10-23/final'
PROJECT = 'ffmadtrcirrzywdqahbu'
ROLE = 'capacity_benchmark'


def fixed_case(body):
    if not isinstance(body, dict) or set(body) != {'caseId', 'engine', 'inputSha256', 'problem'}:
        raise ValueError('Invalid fixed-case request')
    if body['engine'] not in ('DATABASE', 'SOLVER'):
        raise ValueError('Invalid engine')
    rows = json.loads((FIXTURES / 'results.json').read_text())['rows']
    row = next((r for r in rows if r['id'] == body['caseId']), None)
    if row is None or row['outcome'] != 'EQUIVALENT':
        raise ValueError('Unknown fixed case')
    raw = (FIXTURES / 'inputs' / (row['id'] + '.json')).read_bytes()
    if hashlib.sha256(raw).hexdigest() != row['inputSha256'] or body['inputSha256'] != row['inputSha256']:
        raise ValueError('Fixture integrity failure')
    problem = json.loads(raw)
    if json.dumps(problem, sort_keys=True) != json.dumps(body['problem'], sort_keys=True):
        raise ValueError('Fixed input mismatch')
    return problem


def connect_database():
    import psycopg
    url = os.environ.get('CAPACITY_DATABASE_URL', '')
    parsed = urlsplit(url)
    user = unquote(parsed.username or '')
    direct = parsed.hostname == 'db.' + PROJECT + '.supabase.co' and user == ROLE
    pooled = (parsed.hostname or '').endswith('.pooler.supabase.com') and user == ROLE + '.' + PROJECT
    if parsed.scheme not in ('postgres', 'postgresql') or parsed.path != '/postgres' or not (direct or pooled) or parsed.query or parsed.fragment:
        raise ValueError('Use the approved project restricted direct/session connection without URL options')
    if pooled and parsed.port != 5432:
        raise ValueError('Use session pooling on port 5432, not transaction pooling')
    return psycopg.connect(url, autocommit=True, connect_timeout=5,
        sslmode='verify-full', sslrootcert=os.environ.get('CAPACITY_DATABASE_CA_FILE') or ssl.get_default_verify_paths().cafile,
        options='-c default_transaction_read_only=on -c statement_timeout=60000 -c lock_timeout=1000 -c search_path=pg_catalog')


def database_ready(conn):
    row = conn.execute("""select current_setting('transaction_read_only'),current_setting('server_version'),
      r.rolsuper,r.rolcreatedb,r.rolcreaterole,r.rolbypassrls,r.rolinherit,current_database(),current_user,
      to_regprocedure('capacity_reference.timed_offer(jsonb)') is not null,
      exists(select 1 from pg_auth_members where member=r.oid),
      has_schema_privilege(current_user,'public','CREATE'),
      exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
             where n.nspname='capacity_reference' and p.proowner=r.oid)
      from pg_roles r where r.rolname=current_user""").fetchone()
    if not row or row[0] != 'on' or any(row[2:7]) or row[7:9] != ('postgres', ROLE) or not row[9] or any(row[10:]):
        raise RuntimeError('Restricted benchmark connection is not ready')
    return row[1]


def calculate(body):
    problem = fixed_case(body)
    deployment = {'revision': os.environ.get('CAPACITY_RELEASE_ID', 'unlabelled'),
                  'topology': 'existing-app-local-worker', 'pythonVersion': sys.version.split()[0],
                  'ortoolsVersion': importlib.metadata.version('ortools'), 'workerMode': 'one-shot',
                  'admission': 'one test per app process; serial caller required across replicas',
                  'modelSha256': hashlib.sha256((ROOT / 'cargo_capacity.py').read_bytes()).hexdigest()}
    if body['engine'] == 'SOLVER':
        sys.path.insert(0, str(ROOT))
        from cargo_capacity import solve_capacity
        print(json.dumps({'ready': True}), flush=True)
        started = time.perf_counter_ns()
        result = solve_capacity(problem)
        measured = {'result': result, 'calculationMilliseconds': (time.perf_counter_ns() - started) / 1_000_000}
    else:
        print(json.dumps({'ready': True}), flush=True)
        with connect_database() as conn:
            deployment['postgresVersion'] = database_ready(conn)
            measured = conn.execute('select capacity_reference.timed_offer(%s::jsonb)', (json.dumps(problem),)).fetchone()[0]
        deployment['databaseEngine'] = 'current Supabase native PostgreSQL'
    return {**measured, 'engine': body['engine'], 'inputSha256': body['inputSha256'], 'deployment': deployment}


if __name__ == '__main__':
    try:
        # A pipe request is bounded even if invoked outside the HTTP adapter.
        raw = sys.stdin.buffer.read(256_001)
        if len(raw) > 256_000:
            raise ValueError('Oversized input')
        print(json.dumps(calculate(json.loads(raw))), flush=True)
    except Exception:
        # No connection strings, passwords or raw PostgreSQL exceptions on output.
        print(json.dumps({'error': 'Benchmark unavailable; no maximum confirmed'}), file=sys.stderr)
        raise SystemExit(1)
