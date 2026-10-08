"""Synthetic B747F-scale benchmark for the WAB AUTOLOAD model."""
from cp_sat_solver import solve


def benchmark_problem(load_count=100, position_count=120):
    return {
        "version": 1,
        "timeLimitSeconds": 10,
        "idealTrimIndexScaled": 6_000_000,
        "loads": [
            {"id": f"LOAD{i + 1:03}", "description": f"Station {i % 4}", "loadType": "ULD", "weightKg": 700 + (i * 37) % 2600, "uldCode": "PAG", "unloadOrder": i % 4, "lockedPositionId": None}
            for i in range(load_count)
        ],
        "positions": [
            {"id": f"P{i + 1:03}", "description": f"B747 position {i + 1}", "loadType": "ULD", "acceptedUldCodes": ["PAG"], "maximumWeightKg": 5000, "occupiedBayIds": [f"B{i + 1:03}"], "handlingRank": i, "simplicityGroup": "MAIN" if i < 80 else "LOWER", "indexPerKgScaled": 400 + i * 3}
            for i in range(position_count)
        ],
    }


if __name__ == "__main__":
    result = solve(benchmark_problem())
    print(f"{result['engine']}: {result['status']} · {len(result['assignments'])} loads · {result['solveMilliseconds']} ms")
    if result["status"] not in ("OPTIMAL", "FEASIBLE") or len(result["assignments"]) != 100:
        raise SystemExit(1)
