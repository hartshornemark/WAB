import unittest

from cp_sat_solver import solve


class CpSatSolverTest(unittest.TestCase):
    def problem(self):
        return {
            "version": 1,
            "timeLimitSeconds": 3,
            "idealTrimIndexScaled": 1000,
            "loads": [
                {"id": "EARLY", "description": "BKK", "loadType": "ULD", "weightKg": 900, "uldCode": "AKH", "unloadOrder": 0, "lockedPositionId": None},
                {"id": "LATE", "description": "DWC", "loadType": "ULD", "weightKg": 800, "uldCode": "AKH", "unloadOrder": 1, "lockedPositionId": None},
            ],
            "positions": [
                {"id": "FWD", "description": "FWD", "loadType": "ULD", "acceptedUldCodes": ["AKH"], "maximumWeightKg": 1588, "occupiedBayIds": ["1"], "handlingRank": 0, "simplicityGroup": "LOWER", "indexPerKgScaled": 1},
                {"id": "AFT", "description": "AFT", "loadType": "ULD", "acceptedUldCodes": ["AKH"], "maximumWeightKg": 1588, "occupiedBayIds": ["2"], "handlingRank": 1, "simplicityGroup": "LOWER", "indexPerKgScaled": 2},
            ],
        }

    def test_assigns_every_load_and_respects_unload_order(self):
        solution = solve(self.problem())
        self.assertIn(solution["status"], ("OPTIMAL", "FEASIBLE"))
        self.assertEqual(dict((row["loadId"], row["positionId"]) for row in solution["assignments"]), {"EARLY": "FWD", "LATE": "AFT"})
        self.assertEqual(solution["sequencePenalty"], 0)

    def test_respects_locked_assignment(self):
        problem = self.problem()
        problem["loads"][0]["lockedPositionId"] = "AFT"
        solution = solve(problem)
        self.assertEqual(dict((row["loadId"], row["positionId"]) for row in solution["assignments"])["EARLY"], "AFT")

    def test_rejects_overlapping_footprints(self):
        problem = self.problem()
        problem["positions"][1]["occupiedBayIds"] = ["1"]
        solution = solve(problem)
        self.assertEqual(solution["status"], "INFEASIBLE")

    def test_allows_bulk_consignments_to_share_an_area_within_its_limit(self):
        problem = self.problem()
        problem["loads"] = [
            {"id": "B1", "description": "Bulk 1", "loadType": "BULK", "weightKg": 120, "uldCode": None, "unloadOrder": 0, "lockedPositionId": None},
            {"id": "B2", "description": "Bulk 2", "loadType": "BULK", "weightKg": 130, "uldCode": None, "unloadOrder": 0, "lockedPositionId": None},
        ]
        problem["positions"] = [
            {"id": "BULK", "description": "Bulk area", "loadType": "BULK", "acceptedUldCodes": [], "maximumWeightKg": 300, "occupiedBayIds": ["BULK"], "handlingRank": 0, "simplicityGroup": "BULK", "indexPerKgScaled": 0}
        ]
        solution = solve(problem)
        self.assertIn(solution["status"], ("OPTIMAL", "FEASIBLE"))
        self.assertEqual(len(solution["assignments"]), 2)


if __name__ == "__main__":
    unittest.main()
