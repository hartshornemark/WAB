import test from "node:test";
import assert from "node:assert/strict";
import { buildCompactHoldBoard, compactHoldBoardEnabled } from "../src/domain/compact-hold-board";
import { a350HoldBoardFixture } from "./fixtures/a350-hold-board";
import { validateLoadPlanningSolution } from "../src/domain/load-planning-solver";

test("A350 draws every saved atomic bay and maps every AUTOLOAD position without mutation", () => {
  const { d2, d3, d4, problem } = a350HoldBoardFixture(), before = JSON.stringify({ d2, d3, d4, problem });
  const board = buildCompactHoldBoard(d2, d3, d4, problem.positions, null);
  assert.deepEqual(board.errors, []);
  assert.deepEqual(board.groups.map(group => [group.label, group.columns]), [["BULK", 1], ["AFT LOWER DECK", 8], ["FWD LOWER DECK", 11]]);
  assert.equal(board.groups.flatMap(group => group.cells).length, 41); // 38 D3 bays + 3 D2 areas
  const ids = new Set(board.groups.flatMap(group => [...group.cells, ...group.footprints].flatMap(item => item.positionIds)));
  assert.equal(ids.size, problem.positions.length);
  assert.equal(JSON.stringify({ d2, d3, d4, problem }), before);
  assert.ok(board.groups[2].cells.some(cell => cell.label === "13L"));
});

test("A350 lane order, pair and pallet footprints come from exact solver occupancy", () => {
  const { d2, d3, d4, problem } = a350HoldBoardFixture();
  const board = buildCompactHoldBoard(d2, d3, d4, problem.positions, null);
  const aft = board.groups[1];
  assert.deepEqual(aft.cells.filter(cell => cell.lane === "L").map(cell => cell.label), ["45L", "44L", "43L", "42L", "41L", "33L", "32L", "31L"]);
  for (const group of board.groups) for (const footprint of group.footprints) for (const id of footprint.positionIds) {
    assert.deepEqual([...problem.positions.find(position => position.id === id)!.occupiedBayIds].sort(), footprint.cellKeys);
  }
  assert.ok(board.groups[2].footprints.some(item => item.kind === "PAIR"));
  assert.ok(board.groups[2].footprints.some(item => item.label === "12P" && item.span === 3));
});

test("drawing cannot invent missing bay structure or remap unknown occupancy to a nearby bay", () => {
  const { d2, d3, d4, problem } = a350HoldBoardFixture();
  d3.configurations[0].atomicBays[0].balanceFrom = null;
  assert.match(buildCompactHoldBoard(d2, d3, d4, problem.positions, null).errors.join(" "), /physical From\/To/);
  problem.positions[0].occupiedBayIds = ["MISSING:BAY"];
  assert.match(buildCompactHoldBoard(d2, d3, d4, problem.positions, null).errors.join(" "), /missing physical bay/);
});

test("D4 creates one external marker per saved door and preserves L/R orientation", () => {
  const { d2, d3, d4, problem } = a350HoldBoardFixture();
  const board = buildCompactHoldBoard(d2, d3, d4, problem.positions, null);
  assert.deepEqual(board.groups.flatMap(group => group.doors).map(door => [door.holdId, door.anchorRef, door.orientation, door.edge]), [
    ["LOWER:ALB", "52", "R", "BOTTOM"], ["LOWER:ALA", "43", "L", "TOP"], ["LOWER:FLF", "12P", "R", "BOTTOM"],
  ]);
  assert.equal(board.groups[1].doors[0].column, 2); // 45, 44, then 43
  assert.equal(board.groups[2].doors[0].column, 7); // D4 12P occupies 14/13/12 resources
  assert.equal(board.groups[2].doors[0].span, 3);
  assert.match(board.notes.join(" "), /lock states are not supplied/);
  d4.doorsActive = false;
  const withoutDoors = buildCompactHoldBoard(d2, d3, d4, problem.positions, null);
  assert.ok(withoutDoors.groups.every(group => group.doors.length === 0));
  assert.deepEqual(withoutDoors.groups.map(group => ({ ...group, doors: [] })), board.groups.map(group => ({ ...group, doors: [] })));
});

test("a pallet and an individual bay sharing its footprint are rejected by the same move/AUTOLOAD validator", () => {
  const { d2, d3, d4, problem } = a350HoldBoardFixture();
  const board = buildCompactHoldBoard(d2, d3, d4, problem.positions, null);
  const footprint = board.groups[2].footprints.find(item => item.label === "11P")!;
  const pallet = problem.positions.find(position => footprint.positionIds.includes(position.id))!;
  const bay = problem.positions.find(position => position.occupiedBayIds.length === 1 && footprint.cellKeys.includes(position.occupiedBayIds[0]) && position.acceptedUldCodes.includes("AKE"))!;
  const first = { ...problem.loads[0], id: "pallet", uldCode: pallet.acceptedUldCodes[0] }, second = { ...problem.loads[0], id: "bay" };
  assert.throws(() => validateLoadPlanningSolution({ ...problem, loads: [first, second] }, { status: "FEASIBLE", engine: "test", solveMilliseconds: 0, assignments: [{ loadId: first.id, positionId: pallet.id }, { loadId: second.id, positionId: bay.id }], sequencePenalty: 0, usedSimplicityGroups: 1, trimDeviationScaled: null, messages: [] }), /overlapping assignment/);
});

test("compact renderer rollout is limited to the A350", () => {
  assert.equal(compactHoldBoardEnabled("359"), true);
  for (const type of ["319", "320", "321", "333", "763", "77W", "744"]) assert.equal(compactHoldBoardEnabled(type), false);
});

test("FWD 11–15 are alternatives: 12, 13 and 14 cannot all be occupied together", () => {
  const { d2, d3, d4, problem } = a350HoldBoardFixture();
  const board = buildCompactHoldBoard(d2, d3, d4, problem.positions, null);
  const cells = board.groups[2].cells;
  const targets = ["12L", "13L", "14L"].map(label => {
    const cell = cells.find(item => item.label === label)!;
    return problem.positions.find(position => cell.positionIds.includes(position.id) && position.acceptedUldCodes.includes("AKE"))!;
  });
  assert.ok(targets.every(position => position.occupiedBayIds.includes("LOWER:FLF:13L")));
  const loads = targets.map((_, index) => ({ ...problem.loads[0], id: `alternative-${index}` }));
  assert.throws(() => validateLoadPlanningSolution({ ...problem, loads }, {
    status: "FEASIBLE", engine: "test", solveMilliseconds: 0,
    assignments: targets.map((position, index) => ({ loadId: loads[index].id, positionId: position.id })),
    sequencePenalty: 0, usedSimplicityGroups: 1, trimDeviationScaled: null, messages: [],
  }), /overlapping assignment/);
});


test("door chrome never invents D4 doors from solver flags or replaces a missing anchor with a nearby bay", () => {
  const { d2, d3, d4, problem } = a350HoldBoardFixture();
  assert.ok(problem.positions.some(position => position.doorAnchor));
  const noSavedDoors = buildCompactHoldBoard(d2, d3, { ...d4, doors: [] }, problem.positions, null);
  assert.equal(noSavedDoors.groups.flatMap(group => group.doors).length, 0);
  d4.doors[2].anchorRef = "UNKNOWN";
  const board = buildCompactHoldBoard(d2, d3, d4, problem.positions, null);
  assert.equal(board.groups[1].doors.length, 0);
  assert.deepEqual(board.errors, []); // A door note must not hide the board.
  assert.match(board.notes.join(" "), /D4 door LOWER:ALA \(UNKNOWN\).*cannot be mapped/);
});

test("unmapped bulk, hold and incomplete D4 door records remain visible as configuration notes", () => {
  const { d2, d3, d4, problem } = a350HoldBoardFixture();
  d4.doors[0].anchorRef = "MISSING";
  d4.doors[1].holdId = "LOWER:UNKNOWN";
  d4.doors[2].orientation = null;
  const board = buildCompactHoldBoard(d2, d3, d4, problem.positions, null);
  assert.equal(board.groups.flatMap(group => group.doors).length, 0);
  assert.deepEqual(board.errors, []);
  assert.match(board.notes.join(" "), /LOWER:ALB.*cannot be mapped/);
  assert.match(board.notes.join(" "), /LOWER:UNKNOWN.*saved hold is not on/);
  assert.match(board.notes.join(" "), /LOWER:ALA.*complete the saved anchor/);
});

test("centre orientation maps only to an anchored external end and never invents an internal door", () => {
  const { d2, d3, d4, problem } = a350HoldBoardFixture();
  const door = d4.doors[2]; door.orientation = "C"; door.anchorRef = "45";
  let board = buildCompactHoldBoard(d2, d3, d4, problem.positions, null);
  assert.equal(board.groups[1].doors[0].edge, "TAIL");
  door.holdId = "LOWER:ALF"; door.anchorRef = "31";
  board = buildCompactHoldBoard(d2, d3, d4, problem.positions, null);
  assert.equal(board.groups[1].doors[0].edge, "NOSE");
  door.holdId = "LOWER:ALA"; door.anchorRef = "43";
  board = buildCompactHoldBoard(d2, d3, d4, problem.positions, null);
  assert.equal(board.groups[1].doors.length, 0);
  assert.match(board.notes.join(" "), /centre orientation needs an anchor at one external end/);
});

test("a D4 compartment anchor maps its own saved cells without altering placement targets", () => {
  const { d2, d3, d4, problem } = a350HoldBoardFixture();
  const baseline = buildCompactHoldBoard(d2, d3, d4, problem.positions, null);
  d4.doors[0].anchorType = "COMPARTMENT"; d4.doors[0].anchorRef = "5";
  const board = buildCompactHoldBoard(d2, d3, d4, problem.positions, null);
  assert.equal(board.groups[0].doors[0].anchorRef, "5");
  assert.deepEqual(board.groups.map(group => [group.cells, group.footprints, group.columns]), baseline.groups.map(group => [group.cells, group.footprints, group.columns]));
});
