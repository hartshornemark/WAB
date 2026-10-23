import { aircraftD2HoldId, bulkHoldIdentity, effectiveAircraftD2Snapshot, type AircraftD2Snapshot } from "./aircraft-d2";
import { effectiveAircraftD3Snapshot, type AircraftD3Snapshot } from "./aircraft-d3";
import type { AircraftD4Snapshot } from "./aircraft-d4";
import type { SolverPosition } from "./load-planning-solver";

export type HoldBoardCell = {
  key: string; label: string; holdId: string; column: number; lane: "L" | "R" | "FULL";
  positionIds: string[];
};
export type HoldBoardFootprint = {
  key: string; label: string; column: number; span: number; lane: "L" | "R" | "FULL";
  positionIds: string[]; cellKeys: string[]; kind: "PAIR" | "PALLET" | "ALTERNATIVE";
};
export type HoldBoardGroup = {
  key: string; label: string; caption: string; deckCode: string; columns: number;
  cells: HoldBoardCell[]; footprints: HoldBoardFootprint[]; doors: HoldBoardDoor[];
};
export type HoldBoardDoor = {
  key: string; holdId: string; anchorRef: string; orientation: "L" | "R" | "C";
  column: number; span: number; edge: "TOP" | "BOTTOM" | "TAIL" | "NOSE";
};
export type CompactHoldBoard = { groups: HoldBoardGroup[]; errors: string[]; notes: string[] };

// Rollout is deliberately separate from the renderer: no type-specific geometry.
export const compactHoldBoardEnabled = (typeCode: string) => typeCode === "359";

/** A compact schematic of saved physical bays, never inferred aircraft structure.
 * Solver IDs and occupancy are the single source for every placement target.
 * Neither selected loads nor assignments participate in building this geometry.
 */
export function buildCompactHoldBoard(
  sourceD2: AircraftD2Snapshot, sourceD3: AircraftD3Snapshot, d4: AircraftD4Snapshot,
  positions: SolverPosition[], fuelConfigurationCode: string | null,
): CompactHoldBoard {
  const d2 = effectiveAircraftD2Snapshot(sourceD2, fuelConfigurationCode);
  const d3 = effectiveAircraftD3Snapshot(sourceD3, fuelConfigurationCode);
  const errors: string[] = [], groups: HoldBoardGroup[] = [], doorNotes: string[] = [];
  const fail = (message: string) => errors.push(message);
  if (!d2.canView || !d3.canView || !d4.canView) return { groups, errors: ["D2/D3/D4 hold configuration is unavailable for this account."], notes: [] };
  if (d2.typeCode !== d3.typeCode || d2.subtype !== d3.subtype || d2.typeCode !== d4.typeCode || d2.subtype !== d4.subtype)
    return { groups, errors: ["D2/D3/D4 aircraft identities do not match."], notes: [] };
  const holds = d2.rows.filter(hold => hold.holdType === "BLK" ? d2.bulkApplicable : d2.uldApplicable)
    .toSorted((a, b) => (b.sortBalanceArm ?? b.balanceTo ?? b.balanceCentroid ?? -Infinity) - (a.sortBalanceArm ?? a.balanceTo ?? a.balanceCentroid ?? -Infinity));
  const cellsByOccupancy = new Map<string, HoldBoardCell>();
  const groupByHold = new Map<string, HoldBoardGroup>();
  for (const hold of holds) {
    const holdId = aircraftD2HoldId(hold), family = hold.holdType === "BLK" ? hold.name : bulkHoldIdentity(hold.name).holdId;
    const key = `${hold.deckCode}:${family}`;
    let group = groups.find(item => item.key === key);
    if (!group) {
      group = { key, label: hold.holdType === "BLK" ? "BULK" : `${family} ${hold.deckCode === "LOWER" ? "LOWER DECK" : hold.deckCode}`,
        caption: hold.holdType === "BLK" ? `HOLD ${hold.compartments.map(item => item.id).join(" / ") || hold.name}` : `${family} HOLD`,
        deckCode: hold.deckCode, columns: 0, cells: [], footprints: [], doors: [] };
      groups.push(group);
    }
    groupByHold.set(holdId, group);
    const holdPositions = positions.filter(position => position.holdId === holdId);
    if (!holdPositions.length) fail(`D2 hold ${hold.name}: no usable AUTOLOAD positions. Complete its D2/D3 configuration.`);
    if (hold.holdType === "BLK") {
      // Areas remain individual targets; no invented bulk boundary or subdivision.
      const areas = hold.compartments.flatMap(compartment => compartment.areas);
      const labels = areas.length ? areas.map(area => area.id) : [hold.name];
      labels.forEach(label => {
        const targets = holdPositions.filter(position => areas.length ? position.locationRef === label : position.locationRef === null);
        if (!targets.length) fail(`D2 hold ${hold.name}, area ${label}: no usable loading position.`);
        group!.cells.push({ key: `${holdId}:${label}`, label, holdId, column: group!.columns, lane: "FULL",
          positionIds: targets.map(position => position.id) });
      });
      group.columns++;
      continue;
    }
    const bays = new Map<string, AircraftD3Snapshot["configurations"][number]["atomicBays"][number]>();
    for (const config of d3.configurations.filter(config => config.holdId === holdId)) for (const bay of config.atomicBays) {
      const previous = bays.get(bay.id);
      if (previous && (previous.balanceFrom !== bay.balanceFrom || previous.balanceTo !== bay.balanceTo))
        fail(`D3 hold ${hold.name}, bay ${bay.id}: configurations have conflicting physical boundaries.`);
      bays.set(bay.id, bay);
    }
    if (!bays.size) fail(`D3 hold ${hold.name}: physical atomic bays are missing.`);
    const columns: Array<{ from: number; to: number; bays: typeof bays extends Map<string, infer T> ? T[] : never }> = [];
    for (const bay of bays.values()) {
      const from = bay.balanceFrom, to = bay.balanceTo;
      if (from === null || to === null || !Number.isFinite(from) || !Number.isFinite(to) || from >= to) {
        fail(`D3 hold ${hold.name}, bay ${bay.id}: supply valid physical From/To boundaries.`); continue;
      }
      let column = columns.find(item => Math.abs(item.from - from) < .00001 && Math.abs(item.to - to) < .00001);
      if (!column) { column = { from, to, bays: [] }; columns.push(column); }
      column.bays.push(bay);
    }
    columns.sort((a, b) => b.from - a.from);
    columns.forEach((column, index) => column.bays.forEach(bay => {
      const lane = /L$/i.test(bay.id) ? "L" : /R$/i.test(bay.id) ? "R" : "FULL";
      if (column.bays.some(other => other.id !== bay.id && (lane === "FULL" || other.id.endsWith(lane))))
        fail(`D3 hold ${hold.name}, bay ${bay.id}: physical bays overlap in the same lane.`);
      const targets = holdPositions.filter(position => position.locationRef === bay.id);
      const cell: HoldBoardCell = { key: `${holdId}:${bay.id}`, label: bay.id, holdId, column: group!.columns + index, lane,
        positionIds: targets.map(position => position.id) };
      group!.cells.push(cell); cellsByOccupancy.set(cell.key, cell);
    }));
    group.columns += columns.length;
  }
  for (const position of positions.filter(position => position.loadType === "ULD")) {
    const group = groupByHold.get(position.holdId);
    const cells = position.occupiedBayIds.map(id => cellsByOccupancy.get(id));
    if (!group || cells.some(cell => !cell)) { fail(`D3 position ${position.locationRef ?? position.id}: occupancy references a missing physical bay.`); continue; }
    const known = cells as HoldBoardCell[];
    if (known.length === 1) continue;
    const indices = [...new Set(known.map(cell => cell.column))].sort((a, b) => a - b);
    if (indices.at(-1)! - indices[0] + 1 !== indices.length) { fail(`D3 position ${position.locationRef}: occupied bays are not contiguous.`); continue; }
    const lane = known.every(cell => cell.lane === "L") ? "L" : known.every(cell => cell.lane === "R") ? "R" : "FULL";
    // A full-width outline must cover both saved lanes in each occupied column.
    if (lane === "FULL" && group.cells.some(cell => indices.includes(cell.column) && !known.includes(cell))) {
      fail(`D3 position ${position.locationRef}: occupancy does not describe a rectangular footprint.`); continue;
    }
    const cellKeys = known.map(cell => cell.key).sort(), key = `${position.holdId}:${position.locationRef}:${cellKeys.join("|")}`;
    const existing = group.footprints.find(item => item.key === key);
    if (existing) existing.positionIds.push(position.id);
    else group.footprints.push({ key, label: position.locationRef ?? position.id, column: indices[0], span: indices.length,
      lane, positionIds: [position.id], cellKeys, kind: lane !== "FULL" ? "ALTERNATIVE" : position.uldType === "LD8" ? "PAIR" : "PALLET" });
  }
  // Every solver position, including bulk, must have a visible target.
  const mapped = new Set(groups.flatMap(group => [...group.cells, ...group.footprints].flatMap(item => item.positionIds)));
  for (const position of positions) if (!mapped.has(position.id)) fail(`Loading position ${position.locationRef ?? position.id} cannot be drawn from D2/D3. Correct its configuration.`);
  if (!groups.length) fail("No applicable D2 holds are configured.");
  // Door chrome comes directly from D4, never from solver flags, assignments,
  // aircraft calibration, or a guessed nearest bay. One marker per saved door.
  if (d4.doorsActive) for (const [index, door] of d4.doors.entries()) {
    const configured = door.anchorType || door.anchorRef || door.orientation || door.forwardArm != null || door.aftArm != null || door.height != null;
    if (!configured) continue;
    const note = (detail: string) => doorNotes.push(`D4 door ${door.holdId}${door.anchorRef ? ` (${door.anchorRef})` : ""}: ${detail}`);
    const hold = holds.find(item => aircraftD2HoldId(item) === door.holdId), group = groupByHold.get(door.holdId);
    if (!hold || !group) { note("its saved hold is not on the applicable board. Check the D4 hold and fitted configuration."); continue; }
    if (!door.anchorType || !door.anchorRef || !door.orientation || !["L", "R", "C"].includes(door.orientation)) { note("complete the saved anchor and L/R/C orientation to draw its external marker."); continue; }
    const holdCells = group.cells.filter(cell => cell.holdId === door.holdId);
    let anchored: HoldBoardCell[] = [];
    if (door.anchorType === "ULD_POSITION") {
      const rows = d3.configurations.filter(config => config.holdId === door.holdId)
        .flatMap(config => config.rows.filter(row => row.rowType === "POSITION" && row.positionId === door.anchorRef));
      const footprints = new Set(rows.map(row => [...row.occupiedBayIds].sort().join("|")));
      if (footprints.size > 1) { note("the anchor has different D3 occupancy variants. Select an unambiguous D4 anchor."); continue; }
      const keys = rows[0]?.occupiedBayIds.map(id => `${door.holdId}:${id}`) ?? [];
      anchored = holdCells.filter(cell => keys.includes(cell.key));
      if (anchored.length !== keys.length) anchored = [];
    } else if (door.anchorType === "AREA") {
      const exists = hold.compartments.some(compartment => compartment.areas.some(area => area.id === door.anchorRef));
      if (exists) anchored = holdCells.filter(cell => cell.label === door.anchorRef);
    } else if (door.anchorType === "COMPARTMENT") {
      const compartment = hold.compartments.find(item => item.id === door.anchorRef);
      if (compartment) {
        const labels = hold.holdType === "BLK" ? compartment.areas.map(area => area.id)
          : d3.configurations.filter(config => config.holdId === door.holdId).flatMap(config => config.atomicBays.filter(bay => bay.compartmentId === door.anchorRef).map(bay => bay.id));
        anchored = holdCells.filter(cell => labels.includes(cell.label));
      }
    }
    if (!anchored.length) { note(`saved ${door.anchorType} anchor cannot be mapped to a displayed hold/cell. Check D2/D3/D4 configuration.`); continue; }
    const column = Math.min(...anchored.map(cell => cell.column)), end = Math.max(...anchored.map(cell => cell.column)) + 1;
    let edge: HoldBoardDoor["edge"] = door.orientation === "L" ? "TOP" : "BOTTOM";
    if (door.orientation === "C") {
      // A centreline door can be external only at a specified end of the group.
      // An internal or both-ended anchor does not establish which end to use.
      const tail = column === 0, nose = end === group.columns;
      if (tail === nose) { note("centre orientation needs an anchor at one external end of the hold; no end is inferred."); continue; }
      edge = tail ? "TAIL" : "NOSE";
    }
    group.doors.push({ key: `${door.holdId}:${index}`, holdId: door.holdId, anchorRef: door.anchorRef,
      orientation: door.orientation, column, span: end - column, edge });
  }
  // The standard D2 family names carry longitudinal meaning even when a bulk
  // centroid is absent or unrelated to its schematic display position.
  const familyRank = (group: HoldBoardGroup) => {
    const family = group.key.slice(group.deckCode.length + 1);
    return family === "ALB" ? 3 : family === "AFT" ? 2 : family === "FWD" ? 1 : 0;
  };
  groups.sort((a, b) => a.deckCode.localeCompare(b.deckCode) || familyRank(b) - familyRank(a));
  return { groups, errors: [...new Set(errors)], notes: ["Overlapping outlines are alternative D3 arrangements, not additional bays. Bay lock states are not supplied by D4.", ...doorNotes] };
}
