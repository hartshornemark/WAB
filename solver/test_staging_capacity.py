import copy
import io
import json
import os
import types
import unittest
from email.message import Message
from unittest.mock import patch
from staging import service


class StagingCapacityTests(unittest.TestCase):
    def test_only_sealed_fixed_cases_are_accepted(self):
        cases = service.registry()
        sha, p = cases['case-01']
        body = {'caseId': 'case-01', 'engine': 'DATABASE', 'inputSha256': sha, 'problem': p}
        self.assertEqual(service.check_request(body, cases), p)
        bad = copy.deepcopy(body); bad['problem']['passengerWeightGrams'] += 1
        with self.assertRaises(ValueError): service.check_request(bad, cases)
        bad = copy.deepcopy(body); bad['problem']['fixedLoads'] = None
        with self.assertRaises(ValueError): service.check_request(bad, cases)
        with self.assertRaises(ValueError): service.check_request({**body, 'engine': 'AUTOLOAD'}, cases)

    def test_solver_child_has_timing_and_proves_the_fixed_infeasible_case(self):
        p = service.registry()['case-07-infeasible'][1]
        result = service.run_solver(p)
        self.assertEqual(result['result']['status'], 'INFEASIBLE')
        self.assertGreater(result['workerStartupMilliseconds'], 0)
        self.assertGreaterEqual(result['calculationMilliseconds'], 0)

    def test_database_connection_is_read_only_and_bounded(self):
        captured = {}
        def connect(url, **kwargs): captured.update(kwargs); return object()
        fake = types.SimpleNamespace(connect=connect)
        with patch.dict('sys.modules', {'psycopg': fake}), patch.dict(os.environ, {'CAPACITY_DATABASE_URL': 'postgresql://redacted'}):
            service.connect_database()
        self.assertIn('default_transaction_read_only=on', captured['options'])
        self.assertIn('statement_timeout=60000', captured['options'])
        self.assertEqual(captured['connect_timeout'], 5)

    def test_readiness_rejects_owner_and_wrong_database(self):
        class Connection:
            row = ('on', '17', False, False, False, 'capacity_staging_reference', True, False)
            def __enter__(self): return self
            def __exit__(self, *_): pass
            def execute(self, _): return self
            def fetchone(self): return self.row
        conn = Connection()
        with patch.object(service, 'connect_database', return_value=conn), patch.dict(os.environ, {'CAPACITY_DATABASE_NAME': 'capacity_staging_reference'}):
            self.assertEqual(service.database_ready(), '17')
            conn.row = ('on', '17', False, False, False, 'capacity_staging_reference', True, True)
            with self.assertRaises(RuntimeError): service.database_ready()
            conn.row = ('on', '17', False, False, False, 'postgres', True, False)
            with self.assertRaises(RuntimeError): service.database_ready()

    def test_handler_checks_auth_before_any_calculation_and_releases_admission(self):
        cases = service.registry(); token = 'a' * 40
        handler_type = service.make_handler(cases, token, {'revision': 'test'})
        handler = object.__new__(handler_type); handler.headers = Message(); handler.path = '/v1/capacity'
        replies = []; handler.reply = lambda status, body: replies.append((status, body))
        handler.do_POST(); self.assertEqual(replies[-1][0], 401)
        body = {'caseId': 'case-01', 'engine': 'DATABASE', 'inputSha256': cases['case-01'][0], 'problem': cases['case-01'][1]}
        raw = json.dumps(body).encode(); handler.headers['Authorization'] = 'Bearer ' + token
        handler.headers['Content-Length'] = str(len(raw)); handler.headers['Content-Type'] = 'application/json'
        handler.rfile = io.BytesIO(raw); handler.connection = types.SimpleNamespace(settimeout=lambda _: None)
        with patch.object(service, 'run_database', side_effect=RuntimeError('secret database URL')):
            handler.do_POST()
        self.assertEqual(replies[-1][0], 503)
        self.assertNotIn('secret', json.dumps(replies[-1][1]))
        self.assertTrue(service.ADMISSION.acquire(blocking=False)); service.ADMISSION.release()

if __name__ == '__main__': unittest.main()
