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

    def test_slides_an_ordered_block_aft_to_improve_trim(self):
        problem = self.problem()
        problem["loads"][0]["weightKg"] = 1000
        problem["loads"][1]["weightKg"] = 1000
        problem["idealTrimIndexScaled"] = 50_000
        problem["positions"] = [
            {"id": f"P{rank}", "description": f"Position {rank}", "loadType": "ULD", "acceptedUldCodes": ["AKH"], "maximumWeightKg": 1588, "occupiedBayIds": [str(rank)], "handlingRank": rank, "simplicityGroup": "MAIN", "indexPerKgScaled": rank * 10, "deckCode": "MAIN"}
            for rank in range(4)
        ]
        solution = solve(problem)
        assigned = {row["loadId"]: row["positionId"] for row in solution["assignments"]}
        self.assertEqual(assigned, {"EARLY": "P2", "LATE": "P3"})
        self.assertEqual(solution["sequencePenalty"], 0)
        self.assertEqual(solution["trimDeviationScaled"], 0)

    def test_does_not_compare_unloading_order_across_separately_accessed_holds(self):
        problem = self.problem()
        problem["positions"][0]["deckCode"] = "LOWER"
        problem["positions"][0]["holdId"] = "FWD"
        problem["positions"][0]["handlingRank"] = 10
        problem["positions"][1]["deckCode"] = "LOWER"
        problem["positions"][1]["holdId"] = "AFT"
        problem["positions"][1]["handlingRank"] = 0
        problem["loads"][0]["lockedPositionId"] = "FWD"
        problem["loads"][1]["lockedPositionId"] = "AFT"
        self.assertEqual(solve(problem)["sequencePenalty"], 0)

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

    def test_rejects_bulk_consignments_over_the_volume_limit(self):
        problem = self.problem()
        problem["loads"] = [
            {"id": "B1", "description": "Bulk 1", "loadType": "BULK", "weightKg": 120, "volumeLitres": 600, "uldCode": None, "unloadOrder": 0, "lockedPositionId": None},
            {"id": "B2", "description": "Bulk 2", "loadType": "BULK", "weightKg": 130, "volumeLitres": 600, "uldCode": None, "unloadOrder": 0, "lockedPositionId": None},
        ]
        problem["positions"] = [
            {"id": "BULK", "description": "Bulk area", "loadType": "BULK", "acceptedUldCodes": [], "maximumWeightKg": 300, "maximumVolumeLitres": 1000, "occupiedBayIds": ["BULK"], "handlingRank": 0, "simplicityGroup": "BULK", "indexPerKgScaled": 0}
        ]
        self.assertEqual(solve(problem)["status"], "INFEASIBLE")

    def test_separates_incompatible_dangerous_goods_by_compartment(self):
        problem = self.problem()
        problem["loads"][0]["dangerousGoodsClasses"] = ["3"]
        problem["loads"][1]["dangerousGoodsClasses"] = ["5.1"]
        problem["positions"][0]["segregationGroup"] = "FWD"
        problem["positions"][1]["segregationGroup"] = "AFT"
        problem["incompatiblePairs"] = [{"left": "DGR:3", "right": "DGR:5.1", "reason": "IATA DGR Table 9.3.A"}]
        solution = solve(problem)
        self.assertIn(solution["status"], ("OPTIMAL", "FEASIBLE"))
        assigned = {row["loadId"]: row["positionId"] for row in solution["assignments"]}
        self.assertNotEqual(assigned["EARLY"], assigned["LATE"])

    def test_rejects_incompatible_dangerous_goods_when_only_one_compartment_exists(self):
        problem = self.problem()
        problem["loads"][0]["dangerousGoodsClasses"] = ["3"]
        problem["loads"][1]["dangerousGoodsClasses"] = ["5.1"]
        for position in problem["positions"]:
            position["segregationGroup"] = "ONE-COMPARTMENT"
        problem["incompatiblePairs"] = [{"left": "DGR:3", "right": "DGR:5.1", "reason": "IATA DGR Table 9.3.A"}]
        self.assertEqual(solve(problem)["status"], "INFEASIBLE")

    def test_applies_h1_special_load_quantity_limit(self):
        problem = self.problem()
        problem["loads"][0]["specialLoadCodes"] = ["AVI"]
        for position in problem["positions"]:
            position["holdId"] = "LOWER"
            position["locationRef"] = position["id"]
        problem["specialLoadLimits"] = [{"code": "AVI", "holdId": "LOWER", "locationRef": None, "maximumQuantity": 0}]
        self.assertEqual(solve(problem)["status"], "INFEASIBLE")


if __name__ == "__main__":
    unittest.main()
