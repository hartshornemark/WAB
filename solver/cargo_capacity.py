"""Read-only capacity search. No operational load assignments or database access."""
from __future__ import annotations

import math
import time
from typing import Any
from ortools.sat.python import cp_model


def validate_problem(problem: dict[str, Any]) -> None:
    if problem.get("mode") != "CARGO_CAPACITY" or problem.get("aircraftType") != "359":
        raise ValueError("Cargo capacity mode is enabled only for A350 type 359.")
    if not isinstance(problem.get("inputRevision"), str) or not problem["inputRevision"].strip() or len(problem["inputRevision"]) > 256:
        raise ValueError("A versioned input snapshot is required.")
    count = problem.get("baggageUldCount")
    if type(count) is not int or not 0 <= count <= 500:
        raise ValueError("Invalid baggage reservation.")
    limit = problem.get("timeLimitSeconds")
    if type(limit) not in (int, float) or not math.isfinite(limit) or not 0 < limit <= 10:
        raise ValueError("Capacity time limit must be positive and at most 10 seconds.")
    positions = problem.get("positions")
    if not isinstance(positions, list) or len(positions) > 500:
        raise ValueError("At most 500 capacity positions are supported.")
    ids = set()
    for p in positions:
        if not isinstance(p.get("id"), str) or not p["id"].strip() or len(p["id"]) > 256 or p["id"] in ids:
            raise ValueError("Capacity position IDs must be unique and nonempty.")
        ids.add(p["id"])
        if p.get("kind") not in ("PALLET", "CONTAINER"):
            raise ValueError("Invalid capacity position kind.")
        bays = p.get("occupiedBayIds")
        if not isinstance(bays, list) or not 1 <= len(bays) <= 100 or any(not isinstance(b, str) or not b.strip() or len(b) > 256 for b in bays) or len(set(bays)) != len(bays):
            raise ValueError("Each capacity position needs unique physical bay resources.")
        if type(p.get("maximumNetWeightGrams")) is not int or not 0 <= p["maximumNetWeightGrams"] <= 100_000_000:
            raise ValueError("Capacity weights must be nonnegative whole grams.")


def solve_capacity(problem: dict[str, Any]) -> dict[str, Any]:
    started = time.perf_counter()
    validate_problem(problem)
    deadline = started + problem["timeLimitSeconds"]
    positions = problem["positions"]
    model = cp_model.CpModel()
    cargo = [model.new_bool_var(f"cargo_{i}") for i in range(len(positions))]
    baggage = {i: model.new_bool_var(f"baggage_{i}") for i, p in enumerate(positions) if p["kind"] == "CONTAINER"}
    model.add(sum(baggage.values()) == problem["baggageUldCount"])
    resources: dict[str, list] = {}
    for i, p in enumerate(positions):
        uses = [cargo[i]] + ([baggage[i]] if i in baggage else [])
        for bay in p["occupiedBayIds"]:
            resources.setdefault(bay, []).extend(uses)
    for uses in resources.values():
        model.add_at_most_one(uses)
    pallet_count = sum(cargo[i] for i, p in enumerate(positions) if p["kind"] == "PALLET")
    container_count = sum(cargo[i] for i, p in enumerate(positions) if p["kind"] == "CONTAINER")
    net_weight = sum(cargo[i] * p["maximumNetWeightGrams"] for i, p in enumerate(positions))
    solver = cp_model.CpSolver()
    solver.parameters.num_search_workers = 1
    solver.parameters.random_seed = 0
    best = None
    proved = []
    status_name = "UNKNOWN"
    for name, objective in (("PALLETS", pallet_count), ("CONTAINERS", container_count), ("NET_WEIGHT", net_weight)):
        remaining = deadline - time.perf_counter()
        if remaining <= 0:
            break
        solver.parameters.max_time_in_seconds = remaining
        model.maximize(objective)
        status = solver.solve(model)
        if status == cp_model.INFEASIBLE:
            status_name = "INFEASIBLE" if best is None else "FEASIBLE"
            break
        if status not in (cp_model.OPTIMAL, cp_model.FEASIBLE):
            break
        best = {
            "palletPositionIds": [p["id"] for i, p in enumerate(positions) if p["kind"] == "PALLET" and solver.value(cargo[i])],
            "containerPositionIds": [p["id"] for i, p in enumerate(positions) if p["kind"] == "CONTAINER" and solver.value(cargo[i])],
            "baggagePositionIds": [positions[i]["id"] for i, v in baggage.items() if solver.value(v)],
            "cargoNetWeightGrams": solver.value(net_weight) if positions else 0,
        }
        status_name = "FEASIBLE"
        # Never freeze an unproved priority and optimise a lower priority.
        if status != cp_model.OPTIMAL:
            break
        proved.append(name)
        model.add(objective == solver.value(objective))
    if len(proved) == 3:
        status_name = "OPTIMAL"
    return {
        "mode": "CARGO_CAPACITY", "aircraftType": "359", "inputRevision": problem["inputRevision"],
        "status": status_name, "engine": "OR-TOOLS CP-SAT", "provedObjectives": proved,
        "solveMilliseconds": round((time.perf_counter() - started) * 1000), "arrangement": best,
    }
