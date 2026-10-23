import json
from pathlib import Path
import unittest
from unittest.mock import patch
from cargo_capacity import solve_capacity, validate_problem
from ortools.sat.python import cp_model


def rule_cases():
    return json.loads((Path(__file__).resolve().parent.parent / 'tests/fixtures/cargo-capacity/rule-unit-cases-v2.json').read_text())['cases']


class CargoCapacityTests(unittest.TestCase):
    def test_agreed_offer_rules_on_small_synthetic_cases(self):
        for c in rule_cases():
            with self.subTest(c['name']):
                result = solve_capacity(c['input'])
                self.assertEqual(result['status'], c['expectedStatus'])
                if result['arrangement'] is not None:
                    self.assertEqual(result['arrangement']['cargoNetWeightGrams'], c['expectedNetGrams'])
                else:
                    self.assertIsNone(c['expectedNetGrams'])

    def test_deadline_does_not_invent_a_maximum(self):
        with patch('cargo_capacity.time.perf_counter', side_effect=[0, 10, 10]):
            result = solve_capacity(rule_cases()[0]['input'])
        self.assertEqual(result['status'], 'UNKNOWN')
        self.assertIsNone(result['arrangement'])

    def test_legacy_and_missing_inputs_are_rejected(self):
        for change in ({'rulesVersion': 'OLD'}, {'groups': None}, {'cargoDensityGramsPerM3': 0}, {'maximumZeroFuelWeightGrams': None}, {'aircraftType': '763'}):
            with self.assertRaises(ValueError):
                validate_problem({**rule_cases()[0]['input'], **change})

    def test_group_cycle_is_rejected(self):
        p = rule_cases()[0]['input']
        p['groups'][0]['parentId'] = 'ROOT'
        with self.assertRaises(ValueError):
            validate_problem(p)

    def test_feasible_is_not_reported_as_a_proved_maximum(self):
        original = cp_model.CpSolver.solve

        def feasible(solver, model):
            original(solver, model)
            return cp_model.FEASIBLE

        with patch.object(cp_model.CpSolver, 'solve', feasible):
            result = solve_capacity(rule_cases()[0]['input'])
        self.assertEqual(result['status'], 'FEASIBLE')
        self.assertIsNotNone(result['arrangement'])


if __name__ == '__main__':
    unittest.main()
