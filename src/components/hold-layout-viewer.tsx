"use client";
import { useEffect, useId, useRef, useState, useTransition } from "react";
import { loadHoldLayout } from "@/app/hold-layout-actions";
import { aircraftLayoutFor, holdLayoutUnavailable, type HoldLayout } from "@/domain/hold-layout";
import type { AircraftD2Snapshot } from "@/domain/aircraft-d2";

export function HoldLayoutViewer({ iata, d2, editing }: { iata: string; d2: AircraftD2Snapshot; editing: boolean }) {
  const [layout, setLayout] = useState<HoldLayout | null>(null);
  const [error, setError] = useState("");
  const [pending, start] = useTransition();
  const reason = holdLayoutUnavailable(d2);
  if (editing) return null;
  return <div className="hold-layout-control">
    <button type="button" className="secondary" disabled={!!reason || pending} title={reason ?? undefined} onClick={() => {
      setError(""); start(async () => {
        const result = await loadHoldLayout(iata, d2.typeCode, d2.subtype);
        if (result.ok) setLayout(result.layout); else setError(result.error);
      });
    }}>{pending ? "Loading layout…" : "VIEW HOLD LAYOUT"}</button>
    {reason && <small>{reason}</small>}
    {error && <small role="alert" className="field-error">{error}</small>}
    {layout && <LayoutDialog iata={iata} layout={layout} onClose={() => setLayout(null)} />}
  </div>;
}
function LayoutDialog({ iata, layout, onClose }: { iata: string; layout: HoldLayout; onClose: () => void }) {
  const ref = useRef<HTMLDialogElement>(null), titleId = useId();
  useEffect(() => { const dialog = ref.current!; dialog.showModal(); return () => dialog.close(); }, []);
  return <dialog className="hold-layout-dialog" ref={ref} aria-labelledby={titleId} onCancel={onClose}>
    <header><div><h2 id={titleId}>HOLD LAYOUT</h2><p>{iata} / {layout.typeCode}-{layout.subtype} · {layout.doorsIncluded ? "Holds and Doors" : "Holds Only — D4 is not yet configured"}</p></div><button type="button" className="secondary" onClick={onClose}>CLOSE</button></header>
    {layout.decks.map(deck => <section key={deck.code} className="hold-layout-deck"><h3>{deck.name}</h3><HoldDiagram layout={layout} deckCode={deck.code}/></section>)}
    <p className="hold-layout-caption">Tail Left · Nose Right. Hold Lengths and Door Positions use saved Balance Arms. Hold Widths are schematic.</p>
  </dialog>;
}
function HoldDiagram({ layout, deckCode }: { layout: HoldLayout; deckCode: string }) {
  const aircraft = aircraftLayoutFor(layout.typeCode, layout.subtype)!;
  const holds = layout.holds.filter(h => h.deckCode === deckCode), doors = layout.doors.filter(d => d.deckCode === deckCode);
  const hasLeft = doors.some(d => d.orientation === "L");
  const viewWidth = 236, viewHeight = hasLeft ? 81.25 : 72;
  const viewX = aircraft.tailX - aircraft.span / 2 - viewWidth / 2;
  const viewY = aircraft.centreY - viewHeight / 2;
  return <svg className="hold-layout-svg" viewBox={`${viewX} ${viewY} ${viewWidth} ${viewHeight}`} role="img" aria-label={`${deckCode}: ${holds.map(h => `Hold ${h.name}`).join("; ")}${layout.doorsIncluded ? "; doors shown" : "; no doors shown"}`}>
    <image href={aircraft.asset} x="102" y="327.25" width="236" height="72"/>
    {holds.map(hold => {
      return <g key={hold.name}><title>Hold {hold.name}; Balance Arm {hold.balanceFrom!.toFixed(3)}–{hold.balanceTo!.toFixed(3)} m</title>
        <rect x={hold.x} y={aircraft.holdY} width={hold.width} height={aircraft.holdHeight} rx={Math.min(6.2, aircraft.holdHeight/4)} fill="none" stroke="#939393" strokeWidth="0.32"/>
        {hold.subdivisions.map(segment => <g key={`${segment.kind}-${segment.compartmentId}-${segment.id}`}>
          <title>{segment.kind === "BAY" ? "Bay" : segment.kind === "AREA" ? "Area" : segment.kind === "COMPARTMENT" ? "Compartment" : "Hold"} {segment.id}</title>
          {segment.kind !== "HOLD" && <rect x={segment.x + .35} y={aircraft.holdY + .35} width={Math.max(0, segment.width - .7)} height={aircraft.holdHeight - .7}
            rx={Math.min(2.5, aircraft.holdHeight/8)} fill="none" stroke="#7890B7" strokeWidth="0.28" strokeDasharray="1.35 1.05"/>}
          <text x={segment.x + segment.width - 1.15} y={aircraft.holdY + 3.7} textAnchor="end"
            fontSize="2.5" fontWeight="700" fill="#334155">{segment.id}</text>
        </g>)}
      </g>;
    })}
    {doors.map(door => {
      const y = door.orientation === "L" ? aircraft.leftDoorY : door.orientation === "C" ? aircraft.centreY : aircraft.rightDoorY;
      return <g key={door.holdId} fill="#245F9F"><title>Door {door.holdId} · {door.orientation === "L" ? "Left" : door.orientation === "R" ? "Right" : "Centre"}</title>
        <path d={`M${door.x} ${y}h${door.width} M${door.x} ${y-1.4}v2.8 M${door.x+door.width} ${y-1.4}v2.8`} fill="none" stroke="#245F9F" strokeWidth="0.6"/>
        <text x={door.x+door.width/2} y={door.orientation === "L" ? y-2.4 : y+4.9} textAnchor="middle" fontSize="2.5" fontWeight="700">DOOR</text>
      </g>;
    })}
  </svg>;
}
