#!/usr/bin/env python3
"""WAB AUTOLOAD CP-SAT adapter. Reads one JSON problem from stdin and writes one JSON solution."""
from __future__ import annotations

import json
import sys
import time
from typing import Any

from ortools.sat.python import cp_model


def solve(problem: dict[str, Any]) -> dict[str, Any]:
    started = time.perf_counter()
    loads = problem["loads"]
    positions = problem["positions"]
    model = cp_model.CpModel()
    assignment: dict[tuple[int, int], cp_model.IntVar] = {}
    compatible: dict[int, list[int]] = {}

    for load_index, load in enumerate(loads):
        compatible[load_index] = []
        for position_index, position in enumerate(positions):
            fits = load["loadType"] == position["loadType"] and load["weightKg"] <= position["maximumWeightKg"] and (
                load["loadType"] == "BULK" or load["uldCode"] in position["acceptedUldCodes"]
            ) and (
                load["loadType"] != "BULK"
                or load.get("volumeLitres") is None
                or position.get("maximumVolumeLitres") is None
                or load["volumeLitres"] <= position["maximumVolumeLitres"]
            )
            if not fits:
                continue
            variable = model.new_bool_var(f"assign_{load_index}_{position_index}")
            assignment[load_index, position_index] = variable
            compatible[load_index].append(position_index)
        model.add_exactly_one(assignment[load_index, position_index] for position_index in compatible[load_index])
        if load["lockedPositionId"] is not None:
            locked = next(index for index, position in enumerate(positions) if position["id"] == load["lockedPositionId"])
            model.add(assignment[load_index, locked] == 1)

    bay_variables: dict[str, list[cp_model.IntVar]] = {}
    for (load_index, position_index), variable in assignment.items():
        if positions[position_index]["loadType"] == "ULD":
            for bay in positions[position_index]["occupiedBayIds"]:
                bay_variables.setdefault(bay, []).append(variable)
    for variables in bay_variables.values():
        model.add_at_most_one(variables)

    # Bulk entries are consignments. Several may share an area while their
    # combined gross weight remains within the configured area limit.
    for position_index, position in enumerate(positions):
        if position["loadType"] != "BULK":
            continue
        model.add(
            sum(
                loads[load_index]["weightKg"] * variable
                for (load_index, candidate_position), variable in assignment.items()
                if candidate_position == position_index
            )
            <= position["maximumWeightKg"]
        )
        if position.get("maximumVolumeLitres") is not None:
            model.add(
                sum(
                    (loads[load_index].get("volumeLitres") or 0) * variable
                    for (load_index, candidate_position), variable in assignment.items()
                    if candidate_position == position_index
                )
                <= position["maximumVolumeLitres"]
            )

    def load_tokens(load: dict[str, Any]) -> set[str]:
        return {f"CODE:{code}" for code in load.get("specialLoadCodes", [])} | {
            f"DGR:{hazard_class}" for hazard_class in load.get("dangerousGoodsClasses", [])
        }

    # The current aircraft model identifies a configured cargo compartment as
    # the conservative segregation boundary. Incompatible loads may therefore
    # be assigned to different compartments, but never to the same one.
    tokens = [load_tokens(load) for load in loads]
    groups = sorted({position.get("segregationGroup", position["id"]) for position in positions})
    for pair in problem.get("incompatiblePairs", []):
        for left_index in range(len(loads)):
            for right_index in range(left_index + 1, len(loads)):
                conflicts = (pair["left"] in tokens[left_index] and pair["right"] in tokens[right_index]) or (
                    pair["right"] in tokens[left_index] and pair["left"] in tokens[right_index]
                )
                if not conflicts:
                    continue
                for group in groups:
                    left_in_group = [
                        assignment[left_index, position_index]
                        for position_index in compatible[left_index]
                        if positions[position_index].get("segregationGroup", positions[position_index]["id"]) == group
                    ]
                    right_in_group = [
                        assignment[right_index, position_index]
                        for position_index in compatible[right_index]
                        if positions[position_index].get("segregationGroup", positions[position_index]["id"]) == group
                    ]
                    if left_in_group and right_in_group:
                        model.add(sum(left_in_group) + sum(right_in_group) <= 1)

    for limit in problem.get("specialLoadLimits", []):
        variables = []
        for load_index, load in enumerate(loads):
            if limit["code"] not in load.get("specialLoadCodes", []):
                continue
            for position_index in compatible[load_index]:
                position = positions[position_index]
                in_scope = position.get("holdId") == limit["holdId"] and (
                    limit["locationRef"] is None or position.get("locationRef") == limit["locationRef"]
                )
                if in_scope:
                    variables.append(assignment[load_index, position_index])
        if variables:
            model.add(sum(variables) <= limit["maximumQuantity"])

    maximum_rank = max(position["handlingRank"] for position in positions)
    load_ranks: list[cp_model.IntVar] = []
    for load_index in range(len(loads)):
        rank = model.new_int_var(0, maximum_rank, f"handling_rank_{load_index}")
        model.add(rank == sum(positions[position_index]["handlingRank"] * assignment[load_index, position_index] for position_index in compatible[load_index]))
        load_ranks.append(rank)

    sequence_terms: list[cp_model.IntVar] = []
    for earlier in range(len(loads)):
        for later in range(len(loads)):
            if loads[earlier]["unloadOrder"] >= loads[later]["unloadOrder"]:
                continue
            penalty = model.new_int_var(0, maximum_rank, f"sequence_{earlier}_{later}")
            model.add(penalty >= load_ranks[earlier] - load_ranks[later])
            sequence_terms.append(penalty)
    sequence_penalty = model.new_int_var(0, maximum_rank * max(1, len(sequence_terms)), "sequence_penalty")
    model.add(sequence_penalty == sum(sequence_terms))

    group_names = sorted({position["simplicityGroup"] for position in positions})
    group_used: dict[str, cp_model.IntVar] = {group: model.new_bool_var(f"group_{index}") for index, group in enumerate(group_names)}
    for (load_index, position_index), variable in assignment.items():
        model.add(variable <= group_used[positions[position_index]["simplicityGroup"]])
    used_groups = model.new_int_var(0, len(group_names), "used_groups")
    model.add(used_groups == sum(group_used.values()))

    trim_deviation = None
    if problem["idealTrimIndexScaled"] is not None:
        maximum_contribution = sum(load["weightKg"] for load in loads) * max(abs(position["indexPerKgScaled"]) for position in positions)
        total_index = model.new_int_var(-maximum_contribution, maximum_contribution, "total_index")
        model.add(total_index == sum(loads[load_index]["weightKg"] * positions[position_index]["indexPerKgScaled"] * variable for (load_index, position_index), variable in assignment.items()))
        trim_deviation = model.new_int_var(0, maximum_contribution + abs(problem["idealTrimIndexScaled"]), "trim_deviation")
        model.add_abs_equality(trim_deviation, total_index - problem["idealTrimIndexScaled"])

    total_seconds = problem["timeLimitSeconds"]
    deadline = time.perf_counter() + total_seconds
    solver = cp_model.CpSolver()
    solver.parameters.num_search_workers = 8
    solver.parameters.random_seed = 0
    best: dict[str, Any] | None = None
    all_optimal = True

    def capture() -> dict[str, Any]:
        return {
            "assignments": [
                {"loadId": loads[load_index]["id"], "positionId": positions[position_index]["id"]}
                for (load_index, position_index), variable in assignment.items()
                if solver.value(variable)
            ],
            "sequence": solver.value(sequence_penalty),
            "groups": solver.value(used_groups),
            "trim": solver.value(trim_deviation) if trim_deviation is not None else None,
        }

    def optimise(objective: cp_model.IntVar, budget: float) -> int:
        nonlocal best, all_optimal
        remaining = deadline - time.perf_counter()
        if remaining <= 0.05:
            return cp_model.UNKNOWN
        solver.parameters.max_time_in_seconds = max(0.05, min(remaining, budget))
        model.minimize(objective)
        status = solver.solve(model)
        if status in (cp_model.OPTIMAL, cp_model.FEASIBLE):
            best = capture()
            all_optimal = all_optimal and status == cp_model.OPTIMAL
        else:
            return status
        model.add(objective == solver.value(objective))
        return status

    status = optimise(sequence_penalty, total_seconds * 0.45)
    if status not in (cp_model.OPTIMAL, cp_model.FEASIBLE):
        label = "INFEASIBLE" if status == cp_model.INFEASIBLE else "UNKNOWN"
        return result(label, started, [], None, None, None, ["No assignment was found within the configured loading constraints and time limit."])
    if optimise(used_groups, total_seconds * 0.20) not in (cp_model.OPTIMAL, cp_model.FEASIBLE):
        return retained_result(best, started, "The time limit was reached while simplifying the loading pattern.")
    if trim_deviation is not None and optimise(trim_deviation, total_seconds * 0.25) not in (cp_model.OPTIMAL, cp_model.FEASIBLE):
        return retained_result(best, started, "The time limit was reached during Ideal Trim optimisation.")

    tie_break = model.new_int_var(0, len(loads) * len(positions) * len(positions), "tie_break")
    model.add(tie_break == sum((load_index * len(positions) + position_index) * variable for (load_index, position_index), variable in assignment.items()))
    status = optimise(tie_break, max(0.05, deadline - time.perf_counter()))
    if status not in (cp_model.OPTIMAL, cp_model.FEASIBLE):
        return retained_result(best, started, "The time limit was reached during deterministic tie-breaking.")
    assert best is not None
    return result(
        "OPTIMAL" if all_optimal else "FEASIBLE",
        started,
        best["assignments"],
        best["sequence"],
        best["groups"],
        best["trim"],
        ["Every released load was assigned within position, overlap, segregation and special-load quantity constraints."],
    )


def result(status: str, started: float, assignments: list[dict[str, str]], sequence: int | None, groups: int | None, trim: int | None, messages: list[str]) -> dict[str, Any]:
    return {
        "status": status,
        "engine": "OR-TOOLS CP-SAT",
        "solveMilliseconds": round((time.perf_counter() - started) * 1000),
        "assignments": assignments,
        "sequencePenalty": sequence,
        "usedSimplicityGroups": groups,
        "trimDeviationScaled": trim,
        "messages": messages,
    }


def retained_result(best: dict[str, Any] | None, started: float, message: str) -> dict[str, Any]:
    if best is None:
        return result("UNKNOWN", started, [], None, None, None, [message])
    return result("FEASIBLE", started, best["assignments"], best["sequence"], best["groups"], best["trim"], [message, "The best complete valid plan found was retained."])


if __name__ == "__main__":
    try:
        print(json.dumps(solve(json.load(sys.stdin)), separators=(",", ":")))
    except Exception as error:
        print(json.dumps({"error": str(error)}, separators=(",", ":")))
        raise SystemExit(1)
