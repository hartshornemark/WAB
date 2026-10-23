import test from "node:test";
import assert from "node:assert/strict";
import { Children, isValidElement, type ReactNode, type ReactElement, type DragEvent } from "react";
import { CompactHoldBoardView } from "../src/components/compact-hold-board";
import { buildCompactHoldBoard } from "../src/domain/compact-hold-board";
import { a350HoldBoardFixture } from "./fixtures/a350-hold-board";

function elements(node: ReactNode): ReactElement<Record<string, unknown>>[] {
  return Children.toArray(node).flatMap(child => isValidElement<Record<string, unknown>>(child)
    ? [child, ...elements(child.props.children as ReactNode)] : []);
}

function fixture(code: string, pair = false) {
  const { d2, d3, d4, problem } = a350HoldBoardFixture();
  const board = buildCompactHoldBoard(d2, d3, d4, problem.positions, null);
  const footprint = board.groups.flatMap(group => group.footprints).find(item =>
    (pair ? item.kind === "PAIR" : item.kind === "PALLET") && item.positionIds.some(id => problem.positions.find(p => p.id === id)!.acceptedUldCodes.includes(code)))!;
  assert.ok(footprint, `configured ${code} footprint`);
  const load = { ...problem.loads[0], id: "drag-load", uldCode: code, weightKg: 100, volumeLitres: null };
  const moves: Array<[string, string[]]> = [];
  const tree = CompactHoldBoardView({ board, deckCode: "LOWER", positions: problem.positions, assignments: [], loads: new Map([[load.id, load]]), selectedLoadId: load.id,
    onMove: (id, ids) => moves.push([id, ids]), renderLoad: () => null });
  const nodes = elements(tree), target = nodes.find(node => node.props["data-position-ids"] === footprint.positionIds.join("|"))!;
  return { load, footprint, moves, nodes, target };
}

for (const code of ["PAG", "PMC"]) test(`${code} footprint body captures drop and PLACE with the exact solver IDs`, () => {
  const { load, footprint, moves, nodes, target } = fixture(code);
  assert.match(String(target.props.className), /can-place/);
  let prevented = false, stopped = false;
  const event = { preventDefault: () => { prevented = true; }, stopPropagation: () => { stopped = true; }, dataTransfer: { getData: () => load.id, dropEffect: "none" } } as unknown as DragEvent<HTMLElement>;
  (target.props.onDragOver as (event: DragEvent<HTMLElement>) => void)(event);
  assert.ok(prevented && stopped);
  assert.equal(event.dataTransfer.dropEffect, "move");
  (target.props.onDrop as (event: DragEvent<HTMLElement>) => void)(event);
  const label = elements(target.props.children as ReactNode).find(node => node.props.className === "compact-footprint-label")!;
  (label.props.onClick as () => void)();
  assert.deepEqual(moves, [[load.id, footprint.positionIds], [load.id, footprint.positionIds]]);
  assert.ok(nodes.filter(node => node.props["data-bay"]).every(node => !String(node.props.className).includes("can-place")));
});

test("drop attempts reach the move validator even when the target fails basic compatibility", () => {
  const { load, nodes, moves } = fixture("PAG");
  const bay = nodes.find(node => node.props["data-bay"] === "45L")!;
  (bay.props.onDrop as (event: DragEvent<HTMLElement>) => void)({ preventDefault() {}, stopPropagation() {}, dataTransfer: { getData: () => load.id } } as unknown as DragEvent<HTMLElement>);
  assert.equal(moves.length, 1); // Existing move handler supplies the normal error notice.
  assert.equal(moves[0][0], load.id);
  assert.ok(moves[0][1].length);
});

test("single-bay AKE targets remain highlighted and accept drops", () => {
  const { d2, d3, d4, problem } = a350HoldBoardFixture();
  const board = buildCompactHoldBoard(d2, d3, d4, problem.positions, null), load = problem.loads[0];
  const moves: string[][] = [];
  const nodes = elements(CompactHoldBoardView({ board, deckCode: "LOWER", positions: problem.positions, assignments: [], loads: new Map([[load.id, load]]), selectedLoadId: load.id, onMove: (_, ids) => moves.push(ids), renderLoad: () => null }));
  const bay = nodes.find(node => node.props["data-bay"] && String(node.props.className).includes("can-place"))!;
  assert.ok(bay);
  (bay.props.onDrop as (event: DragEvent<HTMLElement>) => void)({ preventDefault() {}, stopPropagation() {}, dataTransfer: { getData: () => load.id } } as unknown as DragEvent<HTMLElement>);
  assert.equal(moves.length, 1);
  const alternative = nodes.find(node => String(node.props.className).includes("compact-footprint alternative") && String(node.props.className).includes("can-place"))!;
  assert.ok(alternative); // AKE alternatives with multiple saved resource bays are also footprint targets.
  assert.ok(elements(alternative.props.children as ReactNode).some(node => node.props.className === "compact-footprint-label" && !node.props.disabled));
});
