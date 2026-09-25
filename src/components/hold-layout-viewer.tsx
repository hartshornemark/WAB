"use client";
import { useEffect, useId, useRef, useState, useTransition } from "react";
import { loadHoldLayout } from "@/app/hold-layout-actions";
import { holdLayoutPrerequisite, type HoldLayout, holdLayoutX } from "@/domain/hold-layout";
import type { AircraftD2Snapshot } from "@/domain/aircraft-d2";

export function HoldLayoutViewer({ iata, d2, editing }: { iata: string; d2: AircraftD2Snapshot; editing: boolean }) {
  const [layout, setLayout] = useState<HoldLayout | null>(null);
  const [error, setError] = useState("");
  const [pending, start] = useTransition();
  const reason = holdLayoutPrerequisite(d2);
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
    <header><div><h2 id={titleId}>HOLD LAYOUT</h2><p>{iata} / {layout.typeCode}-{layout.subtype}</p></div><button type="button" className="secondary" onClick={onClose}>CLOSE</button></header>
    {layout.decks.map(deck => <section key={deck.code} className="hold-layout-deck"><h3>{deck.name}</h3><HoldDiagram layout={layout} deckCode={deck.code}/></section>)}
    <p className="hold-layout-caption">Tail Left · Nose Right. {layout.usesGlobalHoldBoundaries ? "Hold lengths use the global aircraft-type boundaries where optional carrier boundaries are absent." : "Hold lengths use saved carrier Balance Arms."} {layout.calibration.diagramCaption ?? "Aircraft doors are shown in the official plan. Hold widths are schematic."}</p>
  </dialog>;
}
function HoldDiagram({ layout, deckCode }: { layout: HoldLayout; deckCode: string }) {
  const [imageFailed,setImageFailed]=useState(false);
  if(imageFailed)return <p role="alert" className="field-error">The aircraft outline could not be loaded. Close this view and open it again to retry.</p>;
  const aircraft = layout.calibration;
  const holds = layout.holds.filter(h => h.deckCode === deckCode);
  const viewWidth = aircraft.imageFrame.width, viewHeight = aircraft.imageFrame.height;
  const viewX = aircraft.tailX - aircraft.span / 2 - viewWidth / 2;
  const viewY = aircraft.centreY - viewHeight / 2;
  const image = aircraft.imageFrame;
  return <svg className="hold-layout-svg" viewBox={`${viewX} ${viewY} ${viewWidth} ${viewHeight}`} role="img" aria-label={`${deckCode}: ${holds.map(h => `Hold ${h.name}`).join("; ")}`}>
    <image onError={()=>setImageFailed(true)} href={aircraft.asset} x={image.x} y={image.y} width={image.width} height={image.height}/>
    {holds.map(hold => {
      const profile=aircraft.combinedHoldProfile;
      if(profile && hold.holdType==="BLK") {
        const halfAt=(arm:number)=>{const points=profile.points;const next=points.findIndex(p=>p.arm>=arm);if(next<0)return points[points.length-1].halfWidth;if(next===0)return points[0].halfWidth;const a=points[next-1],b=points[next];return a.halfWidth+(b.halfWidth-a.halfWidth)*(arm-a.arm)/(b.arm-a.arm)};
        const from=hold.balanceFrom!,to=hold.balanceTo!;
        const stations=[from,...profile.points.filter(p=>p.arm>from&&p.arm<to).map(p=>p.arm),to];
        const points=[...stations.map(arm=>`${holdLayoutX(arm,aircraft)},${aircraft.centreY-halfAt(arm)}`),...stations.toReversed().map(arm=>`${holdLayoutX(arm,aircraft)},${aircraft.centreY+halfAt(arm)}`)].join(" ");
        const labels=hold.subdivisions;
        const forward=labels.at(-1)?.id??hold.name,aft=labels[0]?.id??hold.name;
        return <g key={hold.name}><title>Hold {hold.name}; stations {from}–{to} {aircraft.armUnit??"M"}</title>
          <polygon points={points} fill="#edf1f6" fillOpacity="0.5" stroke="#939393" strokeWidth="0.32"/>
          {profile.joinArm>from&&profile.joinArm<to&&<path d={`M ${holdLayoutX(profile.joinArm,aircraft)} ${aircraft.centreY-halfAt(profile.joinArm)} V ${aircraft.centreY+halfAt(profile.joinArm)}`} stroke="#7890B7" strokeWidth="0.28" strokeDasharray="1.35 1.05"><title>Indicative join at station {profile.joinArm}; not a confirmed compartment boundary</title></path>}
          <text x={hold.x+hold.width-1.15} y={aircraft.centreY-halfAt(from)+3.7} textAnchor="end" fontSize="2.5" fontWeight="700" fill="#334155">{forward}</text>
          {labels.length>1&&<text x={hold.x+1.15} y={aircraft.centreY-halfAt(to)+3.7} textAnchor="start" fontSize="2.5" fontWeight="700" fill="#334155">{aft}</text>}
        </g>;
      }
      return <g key={hold.name}><title>Hold {hold.name}; Balance Arm {hold.balanceFrom!.toFixed(3)}–{hold.balanceTo!.toFixed(3)} {aircraft.armUnit??"M"}</title>
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
  </svg>;
}
