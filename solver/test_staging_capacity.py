import copy
import json
import os
import types
import unittest
from unittest.mock import patch
from staging import app_worker as worker


def body(engine='SOLVER'):
    rows = json.loads((worker.FIXTURES / 'results.json').read_text())['rows']
    row = next(r for r in rows if r['id'] == 'case-07-infeasible')
    return {'caseId': row['id'], 'engine': engine, 'inputSha256': row['inputSha256'],
            'problem': json.loads((worker.FIXTURES / 'inputs/case-07-infeasible.json').read_text())}


class StagingCapacityTests(unittest.TestCase):
    def test_only_sealed_fixed_cases_are_accepted(self):
        b = body(); self.assertEqual(worker.fixed_case(b), b['problem'])
        for change in [lambda b: b.update(engine='AUTOLOAD'), lambda b: b.update(inputSha256='bad'),
                       lambda b: b.update(caseId='../unknown'), lambda b: b['problem'].update(passengerWeightGrams=1),
                       lambda b: b['problem'].update(fixedLoads=None)]:
            bad = copy.deepcopy(b); change(bad)
            with self.assertRaises(ValueError): worker.fixed_case(bad)
        with self.assertRaises(ValueError): worker.fixed_case({**b, 'arbitrary': 1})

    def test_solver_dispatch_requires_no_database_connection(self):
        with patch.object(worker, 'connect_database', side_effect=AssertionError('must not connect')), patch('builtins.print'):
            result = worker.calculate(body())
        self.assertEqual(result['result']['status'], 'INFEASIBLE')
        self.assertGreaterEqual(result['calculationMilliseconds'], 0)
        self.assertEqual(result['deployment']['topology'], 'existing-app-local-worker')

    def test_database_connection_requires_approved_project_restricted_role_tls_and_timeouts(self):
        captured = {}
        def connect(url, **kwargs): captured.update(kwargs); return object()
        fake = types.SimpleNamespace(connect=connect)
        direct = 'postgresql://capacity_benchmark:dummy@db.ffmadtrcirrzywdqahbu.supabase.co:5432/postgres'
        pooled = 'postgresql://capacity_benchmark.ffmadtrcirrzywdqahbu:dummy@aws-0-ap-southeast-1.pooler.supabase.com:5432/postgres'
        with patch.dict('sys.modules', {'psycopg': fake}):
            for url in [direct, pooled]:
                with patch.dict(os.environ, {'CAPACITY_DATABASE_URL': url}): worker.connect_database()
            for url in [direct.replace('capacity_benchmark:', 'postgres:'), direct.replace('ffmadtrcirrzywdqahbu', 'wrong'), pooled.replace(':5432', ':6543'), direct + '?sslmode=disable', direct.replace('/postgres', '/other')]:
                with patch.dict(os.environ, {'CAPACITY_DATABASE_URL': url}):
                    with self.assertRaises(ValueError): worker.connect_database()
        self.assertEqual(captured['sslmode'], 'verify-full')
        self.assertIn('default_transaction_read_only=on', captured['options'])
        self.assertIn('statement_timeout=60000', captured['options'])
        self.assertEqual(captured['connect_timeout'], 5)

    def test_readiness_rejects_elevated_roles_membership_schema_create_and_wrong_database(self):
        class Connection:
            row = ('on', '17', False, False, False, False, False, 'postgres', 'capacity_benchmark', True, False, False, False)
            def execute(self, _): return self
            def fetchone(self): return self.row
        conn = Connection(); self.assertEqual(worker.database_ready(conn), '17')
        good = conn.row
        for i, value in [(0,'off'), (2,True),(3,True),(4,True),(5,True),(6,True),(7,'other'),(8,'postgres'),(9,False),(10,True),(11,True),(12,True)]:
            conn.row = tuple(value if j == i else x for j,x in enumerate(good))
            with self.assertRaises(RuntimeError): worker.database_ready(conn)

    def test_database_core_is_returned_without_replacing_transport_time(self):
        class Connection:
            def __enter__(self): return self
            def __exit__(self, *_): pass
            def execute(self, sql, args):
                self.sql = sql; self.args = args; return self
            def fetchone(self): return ({'result': {'status': 'INFEASIBLE'}, 'calculationMilliseconds': 12},)
        conn = Connection()
        with patch.object(worker,'connect_database',return_value=conn), patch.object(worker,'database_ready',return_value='17'), patch('builtins.print'):
            result = worker.calculate(body('DATABASE'))
        self.assertEqual(conn.sql, 'select capacity_reference.timed_offer(%s::jsonb)')
        self.assertEqual(json.loads(conn.args[0]), body()['problem'])
        self.assertEqual(result['calculationMilliseconds'], 12)
        self.assertEqual(result['deployment']['postgresVersion'], '17')

if __name__ == '__main__': unittest.main()
