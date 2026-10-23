import itertools
import json
from pathlib import Path
import random
import unittest
from unittest.mock import patch

from cargo_capacity import solve_capacity
from ortools.sat.python import cp_model


def a350_problem(baggage=5):
    snapshot = json.loads((Path(__file__).resolve().parent.parent / "tests/fixtures/a350-hold-board.json").read_text())
    positions = []
    for config in snapshot["d3"]["configurations"]:
        for i, row in enumerate(config["rows"]):
            code = row.get("uldCode")
            if row["rowType"] != "POSITION" or code not in ("PAG", "AKE"):
                continue
            positions.append({
                "id": f'{config["holdId"]}:{config["code"]}:{i}:{code}',
                "kind": "PALLET" if code == "PAG" else "CONTAINER",
                "occupiedBayIds": [f'{config["holdId"]}:{b}' for b in row["occupiedBayIds"]],
                "maximumNetWeightGrams": round((min(row["maxWeight"], 4626 if code == "PAG" else 1588) - (110 if code == "PAG" else 100)) * 1000),
            })
    return {"mode": "CARGO_CAPACITY", "aircraftType": "359", "inputRevision": "captured-a350-2026-10-22", "positions": positions, "baggageUldCount": baggage, "timeLimitSeconds": 2}


def objective(problem, result):
    a = result["arrangement"]
    return (len(a["palletPositionIds"]), len(a["containerPositionIds"]), a["cargoNetWeightGrams"])


def check_witness(problem, result):
    a = result["arrangement"]
    assert len(a["baggagePositionIds"]) == problem["baggageUldCount"]
    by_id = {p["id"]: p for p in problem["positions"]}
    used = set()
    net = 0
    for group, kind, cargo in (("palletPositionIds", "PALLET", True), ("containerPositionIds", "CONTAINER", True), ("baggagePositionIds", "CONTAINER", False)):
        for id_ in a[group]:
            p = by_id[id_]
            assert p["kind"] == kind
            assert not used.intersection(p["occupiedBayIds"])
            used.update(p["occupiedBayIds"])
            if cargo:
                net += p["maximumNetWeightGrams"]
    assert net == a["cargoNetWeightGrams"]


class CargoCapacityTests(unittest.TestCase):
    def test_captured_a350_five_baggage_reference(self):
        p = a350_problem()
        result = solve_capacity(p)
        self.assertEqual(result["status"], "OPTIMAL")
        self.assertEqual(objective(p, result)[:2], (7, 3))
        check_witness(p, result)

    def test_empty_and_infeasible(self):
        p = a350_problem(0)
        p["positions"] = []
        self.assertEqual(objective(p, solve_capacity(p)), (0, 0, 0))
        p["baggageUldCount"] = 1
        result = solve_capacity(p)
        self.assertEqual(result["status"], "INFEASIBLE")
        self.assertIsNone(result["arrangement"])

    def test_exhaustive_small_overlap_oracle(self):
        rng = random.Random(350)
        for case in range(20):
            positions = [{"id": str(i), "kind": "PALLET" if i < 2 else "CONTAINER", "occupiedBayIds": sorted(rng.sample(["FWD:11", "FWD:12", "FWD:13", "AFT:41"], rng.randint(1, 2))), "maximumNetWeightGrams": rng.randint(1, 9)*1000} for i in range(6)]
            p = {**a350_problem(case % 3), "positions": positions}
            best = None
            for choices in itertools.product(range(3), repeat=len(positions)):
                used, count, net, pallets, containers = set(), 0, 0, 0, 0
                valid = True
                for choice, pos in zip(choices, positions):
                    if not choice:
                        continue
                    if choice == 2 and pos["kind"] != "CONTAINER" or used.intersection(pos["occupiedBayIds"]):
                        valid = False
                        break
                    used.update(pos["occupiedBayIds"])
                    if choice == 2:
                        count += 1
                    else:
                        pallets += pos["kind"] == "PALLET"
                        containers += pos["kind"] == "CONTAINER"
                        net += pos["maximumNetWeightGrams"]
                if valid and count == p["baggageUldCount"]:
                    best = max(best or (-1, -1, -1), (pallets, containers, net))
            result = solve_capacity(p)
            if best is None:
                self.assertEqual(result["status"], "INFEASIBLE")
            else:
                self.assertEqual(result["status"], "OPTIMAL")
                self.assertEqual(objective(p, result), best)
                check_witness(p, result)

    def test_deadline_never_invents_an_arrangement(self):
        with patch("cargo_capacity.time.perf_counter", side_effect=[0, 10, 10]):
            result = solve_capacity(a350_problem())
        self.assertEqual(result["status"], "UNKNOWN")
        self.assertIsNone(result["arrangement"])

    def test_invalid_inputs(self):
        for change in ({"aircraftType": "763"}, {"baggageUldCount": -1}, {"timeLimitSeconds": float("nan")}, {"inputRevision": ""}):
            with self.assertRaises(ValueError):
                solve_capacity({**a350_problem(), **change})

    def test_unproved_priority_stops_lower_priority_search(self):
        original = cp_model.CpSolver.solve
        calls = []

        def feasible(solver, model):
            calls.append(1)
            original(solver, model)
            return cp_model.FEASIBLE

        with patch.object(cp_model.CpSolver, "solve", feasible):
            result = solve_capacity(a350_problem())
        self.assertEqual(len(calls), 1)
        self.assertEqual(result["status"], "FEASIBLE")
        self.assertEqual(result["provedObjectives"], [])
        check_witness(a350_problem(), result)

    def test_later_timeout_retains_previous_valid_witness(self):
        original = cp_model.CpSolver.solve
        calls = []

        def stop_after_first(solver, model):
            calls.append(1)
            return original(solver, model) if len(calls) == 1 else cp_model.UNKNOWN

        with patch.object(cp_model.CpSolver, "solve", stop_after_first):
            result = solve_capacity(a350_problem())
        self.assertEqual(result["status"], "FEASIBLE")
        self.assertEqual(result["provedObjectives"], ["PALLETS"])
        check_witness(a350_problem(), result)


if __name__ == "__main__":
    unittest.main()
