"use client";

import type { CSSProperties, ReactNode } from "react";
import type { CompactHoldBoard, HoldBoardCell, HoldBoardFootprint } from "@/domain/compact-hold-board";
import type { LoadPlanningAssignment, SolverLoad, SolverPosition } from "@/domain/load-planning-solver";

type Props = {
  board: CompactHoldBoard; deckCode: string; positions: SolverPosition[];
  assignments: LoadPlanningAssignment[]; loads: Map<string, SolverLoad>; selectedLoadId: string | null;
  onMove: (loadId: string, positionIds: string[]) => void;
  renderLoad: (load: SolverLoad, assignment: LoadPlanningAssignment) => ReactNode;
};

export function CompactHoldBoardView({ board, deckCode, positions, assignments, loads, selectedLoadId, onMove, renderLoad }: Props) {
  if (board.errors.length) return <div className="load-control-notice error" role="alert"><strong>Hold board configuration needs attention</strong>{board.errors.map(error => <p key={error}>{error}</p>)}{board.notes.filter(note => note.startsWith("D4 door ")).map(note => <p key={note}>{note}</p>)}</div>;
  const groups = board.groups.filter(group => group.deckCode === deckCode);
  if (!groups.length) return <p role="status">No configured holds on this deck.</p>;
  const selected = selectedLoadId ? loads.get(selectedLoadId) : undefined;
  const byId = new Map(positions.map(position => [position.id, position]));
  const compatible = (ids: string[], load?: SolverLoad) => Boolean(load && ids.some(id => {
    const position = byId.get(id);
    return position && position.loadType === load.loadType && load.weightKg <= position.maximumWeightKg
      && (load.loadType === "BULK" || position.acceptedUldCodes.includes(load.uldCode!))
      && (load.volumeLitres === null || position.maximumVolumeLitres === null || load.volumeLitres <= position.maximumVolumeLitres);
  }));
  const placedAt = (ids: string[]) => assignments.filter(assignment => ids.includes(assignment.positionId));
  const placementEvents = (item: HoldBoardCell | HoldBoardFootprint) => ({
    onDragOver: (event: React.DragEvent<HTMLElement>) => {
      // Let the existing move validator explain invalid attempts as well.
      if (selected) { event.preventDefault(); event.stopPropagation(); }
      event.dataTransfer.dropEffect = selected ? "move" as const : "none" as const;
    },
    onDrop: (event: React.DragEvent<HTMLElement>) => {
      event.preventDefault();
      event.stopPropagation();
      const id = event.dataTransfer.getData("text/plain");
      if (loads.has(id)) onMove(id, item.positionIds);
    },
  });
  const laneStyle = (item: HoldBoardCell | HoldBoardFootprint, columns: number): CSSProperties => ({
    left: `${item.column * 100 / columns}%`, width: `${("span" in item ? item.span : 1) * 100 / columns}%`,
    top: item.lane === "R" ? "50%" : 0, height: item.lane === "FULL" ? "100%" : "50%",
  });
  return <div className="compact-hold-board">
    <div className="compact-hold-direction"><span>TAIL</span><i/><span>NOSE</span></div>
    <div className="compact-hold-line" style={{ gridTemplateColumns: groups.map(group => `${group.columns}fr`).join(" ") }}>
      {groups.map(group => <section className={`compact-hold-group${group.cells.every(cell => cell.lane === "FULL") ? " bulk" : ""}`} key={group.key} aria-label={group.label}>
        <h4>{group.label}</h4>
        <div className="compact-hold-cells">
          {group.cells.map((cell, index) => {
            const direct = placedAt(cell.positionIds).filter(assignment => byId.get(assignment.positionId)?.loadType === "BULK" || byId.get(assignment.positionId)?.occupiedBayIds.length === 1), covering = assignments.filter(assignment => byId.get(assignment.positionId)?.occupiedBayIds.includes(cell.key));
            const occupied = direct.length > 0 || covering.length > 0;
            const isBulk = group.cells.every(item => item.lane === "FULL");
            const canPlace = compatible(cell.positionIds.filter(id => isBulk || byId.get(id)?.occupiedBayIds.length === 1), selected);
            const base = isBulk ? { left: "0%", width: "100%", top: `${index * 100 / group.cells.length}%`, height: `${100 / group.cells.length}%` } : laneStyle(cell, group.columns);
            const style = { left: `calc(${base.left} + .1cqw)`, width: `calc(${base.width} - .2cqw)`,
              top: `calc(${base.top || "0%"} + .1cqw)`, height: `calc(${base.height} - .2cqw)` };
            return <article className={`compact-hold-cell${occupied ? " occupied" : ""}${canPlace ? " can-place" : ""}`} style={style} key={cell.key} data-bay={cell.label} data-position-ids={cell.positionIds.join("|")} {...placementEvents(cell)}>
              <strong>{cell.label}</strong>
              <div className="compact-cell-loads">{direct.map(assignment => {
                const load = loads.get(assignment.loadId); return load ? renderLoad(load, assignment) : null;
              })}</div>
              {direct.length === 0 && <small className="compact-cell-state">{occupied ? "OCCUPIED" : isBulk ? "BULK" : "BAY"}</small>}
              {selected && canPlace && <button className="compact-place" type="button" onClick={() => onMove(selected.id, cell.positionIds)} aria-label={`Place selected load at ${cell.label}`}>PLACE</button>}
            </article>;
          })}
          {group.footprints.map((footprint, index) => {
            const placed = placedAt(footprint.positionIds), canPlace = compatible(footprint.positionIds, selected);
            return <div className={`compact-footprint ${footprint.kind.toLowerCase()}${placed.length ? " occupied" : ""}${canPlace ? " can-place" : ""}`} style={laneStyle(footprint, group.columns)} key={footprint.key} data-position={footprint.label} data-position-ids={footprint.positionIds.join("|")} {...placementEvents(footprint)}>
              {(footprint.kind !== "ALTERNATIVE" || canPlace) && <button type="button" className="compact-footprint-label" style={{ "--label-level": index % 2 } as CSSProperties} disabled={!canPlace} aria-label={`${footprint.label}, ${footprint.cellKeys.length} physical bays${canPlace ? ", place selected load" : ""}`} onClick={() => selected && onMove(selected.id, footprint.positionIds)}>{footprint.label}</button>}
              {placed.length > 0 && <div className="compact-footprint-loads" aria-label={`Load at ${footprint.label}`}><strong className="compact-loaded-position">{footprint.label}</strong>{placed.map(assignment => {
                const load = loads.get(assignment.loadId); return load ? renderLoad(load, assignment) : null;
              })}</div>}
            </div>;
          })}
        </div>
        {group.doors.map(door => <span className={`compact-hold-door ${door.edge.toLowerCase()}`}
          style={door.edge === "TOP" || door.edge === "BOTTOM" ? { left: `calc(.35cqw + (100% - .7cqw) * ${(door.column + door.span / 2) / group.columns})` } : undefined}
          key={door.key} data-door-hold={door.holdId} data-door-anchor={door.anchorRef} data-door-orientation={door.orientation}
          title={`D4 door · ${door.holdId} · ${door.anchorRef} · ${door.orientation}`}
          role="img" aria-label={`D4 door ${door.holdId}, anchor ${door.anchorRef}, ${door.orientation === "L" ? "left side" : door.orientation === "R" ? "right side" : "centreline"}`}>
          DOOR · {door.anchorRef}
        </span>)}
        <small className="compact-hold-caption">{group.caption}</small>
      </section>)}
    </div>
    <div className="compact-hold-legend"><span>CARDS = D3 BAY RESOURCES</span><span>AMBER DOTS = LD8 ARRANGEMENT</span><span>BLUE DASHES = PALLET FOOTPRINT</span><span>ALL HOLDS · ONE LINE · NO HORIZONTAL SCROLL</span></div>
    {board.notes.map(note => <p className="compact-hold-note" key={note}>{note}</p>)}
  </div>;
}
