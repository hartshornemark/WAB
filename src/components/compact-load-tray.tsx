"use client";

import { useEffect, useMemo, useState, type CSSProperties, type ReactNode, type RefObject } from "react";
import type { CompactHoldBoard } from "@/domain/compact-hold-board";
import type { LoadPlanningAssignment, LoadPlanningProblem, SolverLoad } from "@/domain/load-planning-solver";
import { compactTrayBulkVolume, compactTrayItems, trayCategories } from "@/domain/compact-load-tray";

type CardSize = { width: number; height: number; kind: "BULK" | "CELL" | "FOOTPRINT" };
type Props = {
  problem: LoadPlanningProblem; board: CompactHoldBoard; assignments: LoadPlanningAssignment[];
  boardHost: RefObject<HTMLDivElement | null>; action: ReactNode;
  renderLoad: (load: SolverLoad) => ReactNode; onReturnLoad: (id: string) => void;
  formatVolume: (value: number) => string;
};

export function CompactLoadTray({ problem, board, assignments, boardHost, action, renderLoad, onReturnLoad, formatVolume }: Props) {
  const [conflictsOnly, setConflictsOnly] = useState(false);
  const [geometry, setGeometry] = useState<{ unit: number; sizes: Map<string, CardSize> }>({ unit: 0, sizes: new Map() });
  const items = useMemo(() => compactTrayItems(problem, assignments, board), [problem, assignments, board]);
  const volume = useMemo(() => compactTrayBulkVolume(problem, assignments), [problem, assignments]);
  const conflicts = items.filter(item => item.conflict).length;
  const groups = trayCategories.map(category => ({ ...category, items: items.filter(item => item.category === category.key && (!conflictsOnly || item.conflict)) })).filter(group => group.items.length);
  useEffect(() => {
    const host = boardHost.current, surface = host?.querySelector<HTMLElement>(".compact-hold-board");
    if (!host || !surface) return;
    const measure = () => {
      const unit = surface.getBoundingClientRect().width / 100, sizes = new Map<string, CardSize>();
      host.querySelectorAll<HTMLElement>(".compact-hold-cell[data-position-ids]").forEach(cell => {
        const content = cell.querySelector<HTMLElement>(".compact-cell-loads")!, rect = content.getBoundingClientRect();
        for (const id of cell.dataset.positionIds!.split("|")) sizes.set(id, { width: rect.width, height: rect.height, kind: cell.closest(".compact-hold-group.bulk") ? "BULK" : "CELL" });
      });
      // Absolute content insets are the same CSS values used by the board.
      host.querySelectorAll<HTMLElement>(".compact-footprint[data-position-ids]").forEach(target => {
        const rect = target.getBoundingClientRect(), style = getComputedStyle(target);
        const width = rect.width - Number.parseFloat(style.borderLeftWidth) - Number.parseFloat(style.borderRightWidth) - .6 * unit;
        const height = rect.height - Number.parseFloat(style.borderTopWidth) - Number.parseFloat(style.borderBottomWidth) - 2.8 * unit;
        for (const id of target.dataset.positionIds!.split("|")) sizes.set(id, { width, height, kind: "FOOTPRINT" });
      });
      setGeometry({ unit, sizes });
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(surface);
    host.querySelectorAll(".compact-hold-cell,.compact-footprint").forEach(target => observer.observe(target));
    return () => observer.disconnect();
  }, [board, boardHost]);
  return <section className="compact-load-tray" aria-labelledby="load-plan-tray-heading" style={{ "--compact-card-unit": `${geometry.unit}px` } as CSSProperties}
    onDragOver={event => { event.preventDefault(); event.dataTransfer.dropEffect = "move"; }}
    onDrop={event => { event.preventDefault(); const id = event.dataTransfer.getData("text/plain"); if (id) onReturnLoad(id); }}>
    <header><div><p className="eyebrow">LOAD PLAN · AVAILABLE LOAD</p><h3 id="load-plan-tray-heading">Load Tray</h3><p>Unassigned loads awaiting placement</p></div>
      <div className="compact-tray-summary"><span className={items.length ? "attention" : "ready"}><small>UNASSIGNED</small><strong>{items.length} ITEMS</strong></span>
        <span><small>BULK VOLUME</small><strong>{volume.remaining === null ? "NOT CONFIGURED" : `${formatVolume(volume.remaining)} LEFT`}</strong><small>{volume.unassigned === null ? "UNASSIGNED VOLUME UNKNOWN" : `${formatVolume(volume.unassigned)} UNASSIGNED`}</small></span>
        <span className={conflicts ? "conflict" : "ready"}><small>ATTENTION</small><strong>{conflicts} {conflicts === 1 ? "CONFLICT" : "CONFLICTS"}</strong></span></div></header>
    <div className="compact-tray-toolbar"><div aria-label="Load tray filters"><button type="button" className={conflictsOnly ? "secondary" : ""} aria-pressed={!conflictsOnly} onClick={() => setConflictsOnly(false)}>SHOW ALL</button><button type="button" className={conflictsOnly ? "" : "secondary"} aria-pressed={conflictsOnly} onClick={() => setConflictsOnly(true)}>CONFLICTS</button></div><span>Select an item to highlight compatible positions</span>{action}</div>
    <div className="compact-tray-columns" aria-label="Unassigned loads" style={{ "--tray-columns": groups.length || 1 } as CSSProperties}>
      {groups.map(group => <section className="compact-tray-category" aria-label={group.label} key={group.key}><h4>{group.label}</h4><p>{group.items.length} {group.items.length === 1 ? "ITEM" : "ITEMS"}</p><div className="compact-tray-items">
        {group.items.map(item => {
          const size = item.positionId ? geometry.sizes.get(item.positionId) : undefined;
          return <div className="compact-tray-item" key={item.load.id} data-load-id={item.load.id}>
            {size && size.width > 0 && size.height > 0 ? <div className={`compact-tray-card-surface${size.kind === "BULK" ? " compact-tray-bulk" : ""}`} data-size-position={item.positionId} style={{ width: size.width, height: size.height }}>
              {size.kind === "FOOTPRINT" ? <div className="compact-footprint-loads">{renderLoad(item.load)}</div> : renderLoad(item.load)}
            </div> : <div className="compact-tray-unmapped">{renderLoad(item.load)}<small>Board card size unavailable: no matching configured target.</small></div>}
            {item.conflict && <span className="compact-tray-conflict" role="img" aria-label={`Placement conflict: ${item.conflict}`} title={item.conflict}>!</span>}
          </div>;
        })}
      </div></section>)}
      {!groups.length && <p className="compact-tray-empty" role="status">{items.length ? "No unassigned loads have a placement conflict." : "ALL RELEASED LOADS ARE ASSIGNED"}</p>}
    </div>
  </section>;
}
