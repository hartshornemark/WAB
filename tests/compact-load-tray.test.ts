import test from "node:test";
import assert from "node:assert/strict";
import { compactTrayBulkVolume, compactTrayItems, trayCategories, trayCategory } from "../src/domain/compact-load-tray";
import { buildCompactHoldBoard } from "../src/domain/compact-hold-board";
import { a350HoldBoardFixture } from "./fixtures/a350-hold-board";

test("tray groups only unassigned loads into their saved categories, with bulk taking priority", () => {
  const { d2, d3, d4, problem } = a350HoldBoardFixture();
  const base = problem.loads[0];
  problem.loads = [
    { ...base, id: "bag", commodity: "BAGGAGE" }, { ...base, id: "cargo", commodity: "CARGO" },
    { ...base, id: "mail", commodity: "MAIL" }, { ...base, id: "other", commodity: "OTHER" },
    { ...base, id: "bulk", commodity: "BAGGAGE", loadType: "BULK", uldCode: null },
  ];
  assert.deepEqual(problem.loads.map(trayCategory), ["BAGGAGE", "CARGO", "OTHER", "OTHER", "BULK"]);
  const board = buildCompactHoldBoard(d2, d3, d4, problem.positions, null), before = JSON.stringify(problem);
  const items = compactTrayItems(problem, [{ loadId: "mail", positionId: problem.positions[0].id }], board);
  assert.ok(!items.some(item => item.load.id === "mail"));
  const present = trayCategories.filter(category => items.some(item => item.category === category.key));
  assert.deepEqual(present.map(category => category.key), ["BAGGAGE", "CARGO", "OTHER", "BULK"]);
  assert.equal(JSON.stringify(problem), before);
  assert.deepEqual(compactTrayItems(problem, problem.loads.map(load => ({ loadId: load.id, positionId: problem.positions[0].id })), board), []);
});

test("tray conflicts use existing overlap validation and clear when the position is freed", () => {
  const { d2, d3, d4, problem } = a350HoldBoardFixture();
  const position = problem.positions.find(position => position.acceptedUldCodes.includes("AKE") && position.occupiedBayIds.length === 1)!;
  const base = { ...problem.loads[0], weightKg: 100 };
  problem.positions = [position];
  problem.loads = [{ ...base, id: "placed" }, { ...base, id: "waiting" }];
  const board = buildCompactHoldBoard(d2, d3, d4, a350HoldBoardFixture().problem.positions, null);
  const blocked = compactTrayItems(problem, [{ loadId: "placed", positionId: position.id }], board);
  assert.equal(blocked.length, 1);
  assert.match(blocked[0].conflict!, /overlapping assignment/);
  assert.equal(blocked[0].positionId, position.id);
  assert.ok(compactTrayItems(problem, [], board).every(item => item.conflict === null));
  problem.loads[1].uldCode = "UNKNOWN";
  assert.match(compactTrayItems(problem, [], board).find(item => item.load.id === "waiting")!.conflict!, /No configured position/);
});

test("AKE card previews prefer an available single-bay target over multi-bay alternatives", () => {
  const { d2, d3, d4, problem } = a350HoldBoardFixture();
  const board = buildCompactHoldBoard(d2, d3, d4, problem.positions, null);
  const [item] = compactTrayItems(problem, [], board);
  assert.equal(problem.positions.find(position => position.id === item.positionId)!.occupiedBayIds.length, 1);
});

test("bulk summary subtracts assigned volume without inventing unavailable capacity", () => {
  const { problem } = a350HoldBoardFixture();
  const base = problem.loads[0];
  problem.loads = [{ ...base, id: "placed", loadType: "BULK", uldCode: null, volumeLitres: 300 }, { ...base, id: "waiting", loadType: "BULK", uldCode: null, volumeLitres: 200 }];
  problem.positions = problem.positions.filter(position => position.loadType === "BULK");
  problem.positions.forEach(position => { position.maximumVolumeLitres = 1000; });
  const assignments = [{ loadId: "placed", positionId: problem.positions[0].id }];
  assert.deepEqual(compactTrayBulkVolume(problem, assignments), { remaining: problem.positions.length * 1000 - 300, unassigned: 200 });
  problem.positions[0].maximumVolumeLitres = null;
  problem.loads[1].volumeLitres = null;
  assert.deepEqual(compactTrayBulkVolume(problem, assignments), { remaining: null, unassigned: null });
});
