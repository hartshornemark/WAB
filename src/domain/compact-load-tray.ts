import { validateLoadPlanningSolution, type LoadPlanningAssignment, type LoadPlanningProblem, type SolverLoad } from "./load-planning-solver";
import type { CompactHoldBoard } from "./compact-hold-board";

export const trayCategories = [
  { key: "BAGGAGE", label: "Baggage ULDs" }, { key: "CARGO", label: "Cargo ULDs" },
  { key: "OTHER", label: "Mail / Other ULDs" }, { key: "BULK", label: "Bulk Items" },
] as const;
export function trayCategory(load: SolverLoad) {
  if (load.loadType === "BULK") return "BULK";
  if (load.commodity === "BAGGAGE" || load.specialLoadCodes.includes("BAG") || /^B[FJPY]?$/.test(load.commodityCode ?? "")) return "BAGGAGE";
  if (load.commodity === "MAIL" || load.commodity === "OTHER" || load.commodity === "EMPTY") return "OTHER";
  return "CARGO";
}

/** Preview only: the existing independent validator decides availability. */
export function compactTrayItems(problem: LoadPlanningProblem, assignments: LoadPlanningAssignment[], board: CompactHoldBoard) {
  const assignedIds = new Set(assignments.map(item => item.loadId));
  const mapped = new Set(board.groups.flatMap(group => [...group.cells, ...group.footprints].flatMap(target => target.positionIds)));
  return problem.loads.filter(load => !assignedIds.has(load.id)).sort((a, b) => a.unloadOrder - b.unloadOrder || a.description.localeCompare(b.description)).map(load => {
    const candidates = problem.positions.filter(position => mapped.has(position.id) && position.loadType === load.loadType
      && load.weightKg <= position.maximumWeightKg && (!load.uldCode || position.acceptedUldCodes.includes(load.uldCode))
      && (!load.lockedPositionId || load.lockedPositionId === position.id)).sort((a, b) => a.occupiedBayIds.length - b.occupiedBayIds.length);
    let available: string | null = null, reason = "No configured position accepts this load.";
    for (const position of candidates) {
      const next = [...assignments, { loadId: load.id, positionId: position.id }], ids = new Set(next.map(item => item.loadId));
      try {
        validateLoadPlanningSolution({ ...problem, loads: problem.loads.filter(item => ids.has(item.id)) }, {
          status: "FEASIBLE", engine: "tray-preview", assignments: next, solveMilliseconds: 0,
          sequencePenalty: 0, usedSimplicityGroups: 0, trimDeviationScaled: null, messages: [],
        });
        available = position.id; break;
      } catch (error) { reason = error instanceof Error ? error.message : "This placement is not valid."; }
    }
    return { load, category: trayCategory(load), positionId: available ?? candidates[0]?.id ?? null, conflict: available === null ? reason : null };
  });
}

export function compactTrayBulkVolume(problem: LoadPlanningProblem, assignments: LoadPlanningAssignment[]) {
  const positions = problem.positions.filter(position => position.loadType === "BULK");
  const assignedIds = new Set(assignments.map(item => item.loadId));
  const bulk = problem.loads.filter(load => load.loadType === "BULK"), used = bulk.filter(load => assignedIds.has(load.id)), waiting = bulk.filter(load => !assignedIds.has(load.id));
  return {
    remaining: !positions.length || positions.some(position => position.maximumVolumeLitres === null) || used.some(load => load.volumeLitres === null) ? null
      : Math.max(0, positions.reduce((sum, position) => sum + position.maximumVolumeLitres!, 0) - used.reduce((sum, load) => sum + load.volumeLitres!, 0)),
    unassigned: waiting.some(load => load.volumeLitres === null) ? null : waiting.reduce((sum, load) => sum + load.volumeLitres!, 0),
  };
}
