"""A350 cargo offer rules v2: maximum permissible net ULD + Bulk cargo."""
from __future__ import annotations
import math
import time
from ortools.sat.python import cp_model

RULES = "A350_MAX_NET_CARGO_V2"
VOLUME_SCALE = 1_000_000  # millilitres in one cubic metre
MAX_WEIGHT = 1_000_000_000


def integer(value, maximum=MAX_WEIGHT):
    return type(value) is int and 0 <= value <= maximum


def token(value):
    return isinstance(value, str) and 0 < len(value.strip()) <= 256


def validate_problem(p):
    if p.get("mode") != "CARGO_CAPACITY" or p.get("aircraftType") != "359" or p.get("rulesVersion") != RULES or not token(p.get("inputRevision")):
        raise ValueError("A350 cargo offer requires an explicit version-2 input snapshot.")
    if type(p.get("timeLimitSeconds")) not in (int, float) or not math.isfinite(p["timeLimitSeconds"]) or not 0 < p["timeLimitSeconds"] <= 10:
        raise ValueError("Invalid capacity time limit.")
    for key in ("maximumZeroFuelWeightGrams", "dryOperatingWeightGrams", "passengerWeightGrams", "cargoDensityGramsPerM3"):
        if not integer(p.get(key)) or key == "cargoDensityGramsPerM3" and p[key] == 0:
            raise ValueError(f"Missing or invalid {key}.")
    for key, limit in (("positions", 500), ("groups", 100), ("bulkAreas", 100), ("baggageUlds", 100), ("fixedLoads", 500)):
        if not isinstance(p.get(key), list) or len(p[key]) > limit:
            raise ValueError(f"Missing or excessive {key}.")
        ids = [r.get("id") for r in p[key]]
        if any(not token(i) for i in ids) or len(set(ids)) != len(ids):
            raise ValueError(f"Invalid {key} IDs.")
    groups = {r["id"]: r for r in p["groups"]}
    for g in groups.values():
        if not integer(g.get("maximumGrossWeightGrams")) or g.get("maximumBulkVolumeMillilitres", "missing") is not None and not integer(g.get("maximumBulkVolumeMillilitres"), 1_000_000_000):
            raise ValueError("Groups require explicit gross and optional Bulk-volume limits.")
        if "parentId" not in g:
            raise ValueError("Group parent must be explicit.")
        ancestors(g["id"], groups)
    for r in p["positions"]:
        if r.get("kind") not in ("PALLET", "CONTAINER") or r.get("groupId") not in groups:
            raise ValueError("Invalid position kind/group.")
        if not integer(r.get("tareWeightGrams")) or not integer(r.get("maximumGrossWeightGrams")) or r["tareWeightGrams"] > r["maximumGrossWeightGrams"] or not integer(r.get("maximumVolumeMillilitres"), 1_000_000_000):
            raise ValueError("Invalid ULD limits.")
        bays = r.get("occupiedBayIds")
        if not isinstance(bays, list) or not 1 <= len(bays) <= 100 or any(not token(b) for b in bays) or len(bays) != len(set(bays)):
            raise ValueError("Missing ULD footprint.")
    areas = {r["id"]: r for r in p["bulkAreas"]}
    for r in areas.values():
        if r.get("groupId") not in groups or not integer(r.get("maximumGrossWeightGrams")) or not integer(r.get("maximumVolumeMillilitres"), 1_000_000_000):
            raise ValueError("Invalid Bulk area limits.")
    positions = {r["id"]: r for r in p["positions"]}
    for r in p["baggageUlds"]:
        ids = r.get("compatiblePositionIds")
        if not integer(r.get("netWeightGrams")) or not integer(r.get("volumeMillilitres"), 1_000_000_000) or not isinstance(ids, list) or len(ids) > 500 or len(ids) != len(set(ids)) or any(i not in positions or positions[i]["kind"] != "CONTAINER" for i in ids):
            raise ValueError("Baggage needs explicit compatible container IDs, weight and volume.")
    fixed_bays = set()
    for r in p["fixedLoads"]:
        if "bulkAreaId" not in r or "groupId" not in r:
            raise ValueError("Fixed-load location must be explicit.")
        if r.get("kind") not in ("BAGGAGE_BULK", "OTHER") or not integer(r.get("grossWeightGrams")) or not integer(r.get("bulkVolumeMillilitres"), 1_000_000_000):
            raise ValueError("Invalid fixed-load reservation.")
        if r.get("bulkAreaId") is not None:
            if r["bulkAreaId"] not in areas or r.get("groupId") is not None or r.get("occupiedBayIds") != []:
                raise ValueError("Bulk reservations must identify one area only.")
        elif r.get("groupId") not in groups or r.get("kind") == "BAGGAGE_BULK" or r["bulkVolumeMillilitres"] != 0 or not isinstance(r.get("occupiedBayIds"), list) or len(r["occupiedBayIds"]) > 100 or any(not token(b) for b in r["occupiedBayIds"]) or len(r["occupiedBayIds"]) != len(set(r["occupiedBayIds"])):
            raise ValueError("Non-Bulk reservations require a group and explicit occupied bays.")
        if fixed_bays.intersection(r["occupiedBayIds"]):
            raise ValueError("Fixed loads overlap the same physical bay.")
        fixed_bays.update(r["occupiedBayIds"])


def ancestors(group_id, groups):
    result = []
    while group_id is not None:
        if group_id not in groups or group_id in result:
            raise ValueError("Invalid/cyclic hold hierarchy.")
        result.append(group_id)
        group_id = groups[group_id]["parentId"]
    return result


def solve_capacity(p):
    started = time.perf_counter()
    validate_problem(p)
    model = cp_model.CpModel()
    groups = {g["id"]: g for g in p["groups"]}
    positions = p["positions"]
    areas = {a["id"]: a for a in p["bulkAreas"]}
    paths = {g: ancestors(g, groups) for g in groups}
    group_weight = {g: [] for g in groups}
    group_bulk = {g: [] for g in groups}
    fixed_weight = sum(r["grossWeightGrams"] for r in p["fixedLoads"])
    fixed_area_weight = {a: 0 for a in areas}
    fixed_area_volume = {a: 0 for a in areas}
    fixed_group_volume = {g: 0 for g in groups}
    blocked = set()
    for r in p["fixedLoads"]:
        area = areas.get(r["bulkAreaId"])
        group = area["groupId"] if area else r["groupId"]
        for g in paths[group]:
            group_weight[g].append(r["grossWeightGrams"])
            fixed_group_volume[g] += r["bulkVolumeMillilitres"]
        if area:
            fixed_area_weight[area["id"]] += r["grossWeightGrams"]
            fixed_area_volume[area["id"]] += r["bulkVolumeMillilitres"]
        blocked.update(r["occupiedBayIds"])
    active, cargo_weight, baggage_vars = [], [], {}
    resources = {}
    traffic = [fixed_weight]
    for i, pos in enumerate(positions):
        selected = model.new_bool_var(f"cargo_{i}")
        weight = model.new_int_var(0, pos["maximumGrossWeightGrams"] - pos["tareWeightGrams"], f"net_{i}")
        model.add(weight <= (pos["maximumGrossWeightGrams"] - pos["tareWeightGrams"]) * selected)
        model.add(weight >= selected)  # do not report empty cargo ULDs
        uses = [selected]
        gross = weight + pos["tareWeightGrams"] * selected
        for b, bag in enumerate(p["baggageUlds"]):
            if pos["id"] not in bag["compatiblePositionIds"] or bag["netWeightGrams"] + pos["tareWeightGrams"] > pos["maximumGrossWeightGrams"] or bag["volumeMillilitres"] > pos["maximumVolumeMillilitres"]:
                continue
            v = model.new_bool_var(f"bag_{b}_{i}")
            baggage_vars[b, i] = v
            uses.append(v)
            gross += (bag["netWeightGrams"] + pos["tareWeightGrams"]) * v
        for bay in pos["occupiedBayIds"]:
            resources.setdefault(bay, []).extend(uses)
        if blocked.intersection(pos["occupiedBayIds"]):
            for v in uses:
                model.add(v == 0)
        for g in paths[pos["groupId"]]:
            group_weight[g].append(gross)
        traffic.append(gross)
        active.append(selected)
        cargo_weight.append(weight)
    for uses in resources.values():
        model.add_at_most_one(uses)
    for b in range(len(p["baggageUlds"])):
        model.add(sum(v for (bag, _), v in baggage_vars.items() if bag == b) == 1)
    bulk_vars = {}
    for id_, area in areas.items():
        remaining_weight = area["maximumGrossWeightGrams"] - fixed_area_weight[id_]
        remaining_volume = area["maximumVolumeMillilitres"] - fixed_area_volume[id_]
        if remaining_weight < 0 or remaining_volume < 0:
            model.add(False)
        cap = max(0, min(remaining_weight, remaining_volume * p["cargoDensityGramsPerM3"] // VOLUME_SCALE))
        w = model.new_int_var(0, cap, f"bulk_{id_}")
        bulk_vars[id_] = w
        traffic.append(w)
        for g in paths[area["groupId"]]:
            group_weight[g].append(w)
            group_bulk[g].append(w)
    for id_, g in groups.items():
        model.add(sum(group_weight[id_]) <= g["maximumGrossWeightGrams"])
        limit = g["maximumBulkVolumeMillilitres"]
        if limit is not None:
            model.add(sum(group_bulk[id_]) * VOLUME_SCALE <= (limit - fixed_group_volume[id_]) * p["cargoDensityGramsPerM3"])
    model.add(sum(traffic) + p["passengerWeightGrams"] + p["dryOperatingWeightGrams"] <= p["maximumZeroFuelWeightGrams"])
    model.maximize(sum(cargo_weight) + sum(bulk_vars.values()))
    solver = cp_model.CpSolver()
    solver.parameters.num_search_workers = 1
    solver.parameters.random_seed = 0
    remaining = p["timeLimitSeconds"] - (time.perf_counter() - started)
    status = cp_model.UNKNOWN
    if remaining > 0:
        solver.parameters.max_time_in_seconds = remaining
        status = solver.solve(model)
    names = {cp_model.OPTIMAL: "OPTIMAL", cp_model.FEASIBLE: "FEASIBLE", cp_model.INFEASIBLE: "INFEASIBLE"}
    witness = None
    if status in (cp_model.OPTIMAL, cp_model.FEASIBLE):
        cargo = [{"positionId": positions[i]["id"], "netWeightGrams": solver.value(w)} for i, w in enumerate(cargo_weight) if solver.value(active[i])]
        bags = [{"loadId": p["baggageUlds"][b]["id"], "positionId": positions[i]["id"]} for (b, i), v in baggage_vars.items() if solver.value(v)]
        bulk = [{"areaId": id_, "netWeightGrams": solver.value(w)} for id_, w in bulk_vars.items() if solver.value(w)]
        tare = sum(next(pos["tareWeightGrams"] for pos in positions if pos["id"] == r["positionId"]) for r in cargo)
        net = sum(r["netWeightGrams"] for r in cargo + bulk)
        witness = {"cargoUlds": cargo, "baggageUlds": bags, "bulkCargo": bulk, "cargoNetWeightGrams": net, "cargoTareWeightGrams": tare, "cargoGrossWeightGrams": net + tare}
    return {"mode": "CARGO_CAPACITY", "aircraftType": "359", "rulesVersion": RULES, "inputRevision": p["inputRevision"], "status": names.get(status, "UNKNOWN"), "engine": "OR-TOOLS CP-SAT", "solveMilliseconds": round((time.perf_counter() - started) * 1000), "arrangement": witness}
