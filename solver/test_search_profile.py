import hashlib
import json
from pathlib import Path
import unittest
from unittest.mock import patch
from ortools.sat.python import cp_model
from cargo_capacity import solve_capacity
from staging.search_profile import SearchProfile


class SearchProfileTests(unittest.TestCase):
    def test_instrumentation_preserves_model_and_result(self):
        problem = json.loads((Path(__file__).parent / 'verification/a350-v2-seven-scenarios-2026-10-23/final/inputs/case-03.json').read_text())
        original = cp_model.CpSolver.solve
        hashes = []
        def capture(solver, model, callback=None):
            hashes.append(hashlib.sha256(str(model.proto).encode()).hexdigest())
            return original(solver, model, callback)
        observer = SearchProfile()
        with patch.object(cp_model.CpSolver, 'solve', capture):
            plain = solve_capacity(problem)
            profiled = solve_capacity(problem, observer=observer)
        self.assertEqual(hashes[0], hashes[1])
        self.assertEqual(profiled['arrangement']['cargoNetWeightGrams'], plain['arrangement']['cargoNetWeightGrams'])
        report = observer.report(profiled)
        self.assertEqual(report['modelProtoSha256'], hashes[0])
        self.assertEqual(report['bestFoundNetWeightGrams'], 40701000)
        self.assertLessEqual(report['firstValidMilliseconds'], report['bestFoundMilliseconds'])
        if profiled['status'] == 'OPTIMAL':
            self.assertLessEqual(report['bestFoundMilliseconds'], report['proofMilliseconds'])
            self.assertIsNone(report['proofCensoredAtMilliseconds'])
        else:
            self.assertIsNone(report['proofMilliseconds'])
            self.assertGreaterEqual(report['proofCensoredAtMilliseconds'], report['bestFoundMilliseconds'])
        self.assertGreaterEqual(report['processCpuMilliseconds'], 0)
        self.assertTrue(all(a['netWeightGrams'] < b['netWeightGrams'] for a,b in zip(report['improvements'], report['improvements'][1:])))

    def test_narrowed_budget_preserves_the_sealed_input_and_handles_no_search(self):
        problem = json.loads((Path(__file__).parent / 'verification/a350-v2-seven-scenarios-2026-10-23/final/inputs/case-03.json').read_text())
        observer = SearchProfile()
        result = solve_capacity(problem, observer=observer, time_budget_seconds=0.000001)
        report = observer.report(result)
        self.assertEqual(problem['timeLimitSeconds'], 10)
        self.assertEqual(result['status'], 'UNKNOWN')
        self.assertIsNone(report['bestFoundMilliseconds'])
        self.assertIsNone(report['proofMilliseconds'])
        for budget in [0, 11, False, float('nan')]:
            with self.assertRaises(ValueError): solve_capacity(problem, time_budget_seconds=budget)

    def test_unproved_result_never_gets_a_proof_time(self):
        observer = SearchProfile()
        observer.events = [{'netWeightGrams': 10, 'calculationMilliseconds': 2}]
        observer.status = cp_model.FEASIBLE
        observer.ended_ms = 10000
        observer.cpu_ms = 9000
        observer.model_sha256 = 'test'
        observer.preparation_ms = 1
        observer.upper_bound = 11
        observer.solver_wall_ms = 9999
        observer.final_deterministic_time = 1
        observer.branches = observer.conflicts = 0
        report = observer.report({'arrangement': {'cargoNetWeightGrams': 10}})
        self.assertEqual(report['bestFoundMilliseconds'], 2)
        self.assertIsNone(report['proofMilliseconds'])
        self.assertEqual(report['proofCensoredAtMilliseconds'], 10000)
        self.assertEqual(report['absoluteGapGrams'], 1)


if __name__ == '__main__': unittest.main()
