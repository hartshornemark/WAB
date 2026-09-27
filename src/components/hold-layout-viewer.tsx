"use client";
import { useEffect, useId, useRef, useState } from "react";
import { holdLayoutPrerequisite, type HoldLayout, holdLayoutX } from "@/domain/hold-layout";
import type { AircraftD2Snapshot } from "@/domain/aircraft-d2";

export function HoldLayoutViewer({ iata, d2, editing }: { iata: string; d2: AircraftD2Snapshot; editing: boolean }) {
  const [layout, setLayout] = useState<HoldLayout | null>(null);
  const [error, setError] = useState("");
  const [pending, setPending] = useState(false);
  const reason = holdLayoutPrerequisite(d2);
  if (editing) return null;
  return <div className="hold-layout-control">
    <button type="button" className="secondary" disabled={!!reason || pending} title={reason ?? undefined} onClick={async () => {
      setError("");
      setPending(true);
      try {
        const response = await fetch(`/api/carrier/${encodeURIComponent(iata)}/aircraft/${encodeURIComponent(d2.typeCode)}/${encodeURIComponent(d2.subtype)}/hold-layout`, { cache: "no-store" });
        const result = await response.json() as { ok: true; layout: HoldLayout } | { ok: false; error: string };
        if (result.ok) setLayout(result.layout); else setError(result.error);
      } catch {
        setError("Unable to load the saved hold layout. Check your access and try again.");
      } finally {
        setPending(false);
      }
    }}>{pending ? "Loading layout…" : "VIEW HOLD LAYOUT"}</button>
    {reason && <small>{reason}</small>}
    {error && <small role="alert" className="field-error">{error}</small>}
    {layout && <LayoutDialog iata={iata} layout={layout} onClose={() => setLayout(null)} />}
  </div>;
}
function LayoutDialog({ iata, layout, onClose }: { iata: string; layout: HoldLayout; onClose: () => void }) {
  const ref = useRef<HTMLDialogElement>(null), titleId = useId();
  const [selectedUldType,setSelectedUldType]=useState<string|null>(layout.uldTypes[0]??null);
  const [selectedArrangements,setSelectedArrangements]=useState<Record<string,string>>(()=>Object.fromEntries(
    (layout.uldArrangementSelectors??[]).flatMap(selector=>selector.options[0]?[[`${selector.holdId}\0${selector.uldType}`,selector.options[0].id]]:[]),
  ));
  const arrangementSelectors=(layout.uldArrangementSelectors??[]).filter(selector=>selector.uldType===selectedUldType);
  const selectedArrangementLabels=arrangementSelectors.flatMap(selector=>{
    const key=`${selector.holdId}\0${selector.uldType}`;
    const option=selector.options.find(item=>item.id===selectedArrangements[key]);
    return option?[option.label]:[];
  });
  useEffect(() => { const dialog = ref.current!; dialog.showModal(); return () => dialog.close(); }, []);
  return <dialog className="hold-layout-dialog" ref={ref} aria-labelledby={titleId} onCancel={onClose}>
    <header><div><h2 id={titleId}>HOLD LAYOUT</h2><p>{iata} / {layout.typeCode}-{layout.subtype}</p></div><button type="button" className="secondary" onClick={onClose}>CLOSE</button></header>
    {layout.uldTypes.length>0&&<nav className="hold-layout-uld-selectors" aria-label="ULD bay type"><span>ULD BAY TYPE</span>{layout.uldTypes.map(type=><button type="button" className={selectedUldType===type?"selected":""} aria-pressed={selectedUldType===type} key={type} onClick={()=>setSelectedUldType(type)}>{type}</button>)}</nav>}
    {arrangementSelectors.map(selector=>{const key=`${selector.holdId}\0${selector.uldType}`;return <nav className="hold-layout-uld-selectors hold-layout-arrangement-selectors" aria-label={selector.label} key={key}>
      <span>{selector.label}</span>{selector.options.map(option=><button type="button" className={selectedArrangements[key]===option.id?"selected":""} aria-pressed={selectedArrangements[key]===option.id} key={option.id} onClick={()=>setSelectedArrangements(current=>({...current,[key]:option.id}))}>{option.label}</button>)}
    </nav>})}
    {layout.decks.map(deck => <section key={deck.code} className="hold-layout-deck"><h3>{deck.name}</h3><HoldDiagram layout={layout} deckCode={deck.code} selectedUldType={selectedUldType} selectedArrangements={selectedArrangements}/></section>)}
    <p className="hold-layout-caption">Tail Left · Nose Right. {selectedUldType&&`Showing ${selectedUldType} loading positions only. `}{selectedArrangementLabels.length>0&&`Selected arrangement: ${selectedArrangementLabels.join("; ")}. `}{layout.usesGlobalHoldBoundaries ? "Hold lengths use the global aircraft-type boundaries where optional carrier boundaries are absent." : "Hold lengths use saved carrier Balance Arms."} {layout.calibration.diagramCaption ?? "Aircraft doors are shown in the official plan. Hold widths are schematic."}</p>
  </dialog>;
}
function HoldDiagram({ layout, deckCode, selectedUldType, selectedArrangements }: { layout: HoldLayout; deckCode: string; selectedUldType:string|null; selectedArrangements:Record<string,string> }) {
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
      const individualProfile=aircraft.holdProfiles?.[hold.name];
      const profile=individualProfile??aircraft.combinedHoldProfile;
      if(profile && hold.holdType==="BLK") {
        const joinArm=individualProfile?undefined:aircraft.combinedHoldProfile?.joinArm;
        const halfAt=(arm:number)=>{const points=profile.points;const next=points.findIndex(p=>p.arm>=arm);if(next<0)return points[points.length-1].halfWidth;if(next===0)return points[0].halfWidth;const a=points[next-1],b=points[next];return a.halfWidth+(b.halfWidth-a.halfWidth)*(arm-a.arm)/(b.arm-a.arm)};
        const from=hold.balanceFrom!,to=hold.balanceTo!;
        const stations=[from,...profile.points.filter(p=>p.arm>from&&p.arm<to).map(p=>p.arm),to];
        const points=[...stations.map(arm=>`${holdLayoutX(arm,aircraft)},${aircraft.centreY-halfAt(arm)}`),...stations.toReversed().map(arm=>`${holdLayoutX(arm,aircraft)},${aircraft.centreY+halfAt(arm)}`)].join(" ");
        const labels=hold.subdivisions;
        const forward=labels.at(-1)?.id??hold.name,aft=labels[0]?.id??hold.name;
        return <g key={hold.name}><title>Hold {hold.name}; stations {from}–{to} {aircraft.armUnit??"M"}</title>
          <polygon points={points} fill="#edf1f6" fillOpacity="0.5" stroke="#939393" strokeWidth="0.32"/>
          {joinArm!==undefined&&joinArm>from&&joinArm<to&&<path d={`M ${holdLayoutX(joinArm,aircraft)} ${aircraft.centreY-halfAt(joinArm)} V ${aircraft.centreY+halfAt(joinArm)}`} stroke="#7890B7" strokeWidth="0.28" strokeDasharray="1.35 1.05"><title>Indicative join at station {joinArm}; not a confirmed compartment boundary</title></path>}
          <text x={hold.x+hold.width-1.15} y={aircraft.centreY-halfAt(from)+3.7} textAnchor="end" fontSize="2.5" fontWeight="700" fill="#334155">{forward}</text>
          {labels.length>1&&<text x={hold.x+1.15} y={aircraft.centreY-halfAt(to)+3.7} textAnchor="start" fontSize="2.5" fontWeight="700" fill="#334155">{aft}</text>}
        </g>;
      }
      const selector=(layout.uldArrangementSelectors??[]).find(item=>item.holdId===hold.name&&item.uldType===selectedUldType);
      const selectedOption=selector?.options.find(option=>option.id===selectedArrangements[`${selector.holdId}\0${selector.uldType}`]);
      const selectedPositions=selectedUldType?hold.uldPositions.filter(position=>position.uldType===selectedUldType
        &&(!selectedOption||selectedOption.includedPositionIds.includes(position.id))&&!selectedOption?.excludedPositionIds.includes(position.id)).map(position=>{
          const codeRange=selectedOption?.uldCode?position.codeRanges?.find(range=>range.uldCode===selectedOption.uldCode):undefined;
          if(codeRange)return{...position,x:codeRange.x,width:codeRange.width,uldCodes:[codeRange.uldCode]};
          return selectedOption&&position.sourceX!==undefined&&position.sourceWidth!==undefined?{...position,x:position.sourceX,width:position.sourceWidth}:position;
        }):[];
      return <g key={hold.name}><title>Hold {hold.name}; Balance Arm {hold.balanceFrom!.toFixed(3)}–{hold.balanceTo!.toFixed(3)} {aircraft.armUnit??"M"}</title>
        <rect x={hold.x} y={aircraft.holdY} width={hold.width} height={aircraft.holdHeight} rx={Math.min(6.2, aircraft.holdHeight/4)} fill="none" stroke="#939393" strokeWidth="0.32"/>
        {selectedOption?.referencePosition&&<g><title>{selectedOption.label}; {selectedOption.referencePosition.uldCodes.join(", ")} at {selectedOption.referencePosition.id}</title>
          <rect x={selectedOption.referencePosition.x+.35} y={aircraft.holdY+.35} width={Math.max(0,selectedOption.referencePosition.width-.7)} height={aircraft.holdHeight-.7}
            rx={Math.min(2.5,aircraft.holdHeight/4)} fill="#f2d7a1" fillOpacity=".38" stroke="#a47724" strokeWidth=".32"/>
          <text x={selectedOption.referencePosition.x+selectedOption.referencePosition.width/2} y={aircraft.holdY+aircraft.holdHeight/2+.8} textAnchor="middle" fontSize="2.15" fontWeight="700" fill="#71501d">{selectedOption.referencePosition.id}</text>
        </g>}
        {(selectedUldType&&hold.holdType==="ULD"?selectedPositions:hold.subdivisions).map(segment => {
          const isArrangement=!("kind" in segment);
          const label=isArrangement?`${segment.uldType} position`:(segment.kind === "BAY" ? "Bay" : segment.kind === "AREA" ? "Area" : segment.kind === "COMPARTMENT" ? "Compartment" : "Hold");
          const side=isArrangement?(segment.id.trim().toUpperCase().endsWith("L")?"L":segment.id.trim().toUpperCase().endsWith("R")?"R":"FULL"):"FULL";
          const inset=.35,gap=.18,availableHeight=aircraft.holdHeight-inset*2;
          const segmentY=side==="L"?aircraft.holdY+inset:side==="R"?aircraft.holdY+inset+availableHeight/2+gap/2:aircraft.holdY+inset;
          const segmentHeight=side==="FULL"?availableHeight:availableHeight/2-gap/2;
          const labelSize=Math.max(1.05,Math.min(2.5,(segment.width-1)/(Math.max(1,segment.id.length)*.64)));
          return <g key={`${isArrangement?segment.uldType:segment.kind}-${segment.compartmentId}-${segment.id}`}>
            <title>{label} {segment.id}{isArrangement&&segment.uldCodes.length?`; ${segment.uldCodes.join(", ")}`:""}</title>
            {(isArrangement||segment.kind !== "HOLD") && <rect x={segment.x + inset} y={segmentY} width={Math.max(0, segment.width - inset*2)} height={segmentHeight}
              rx={Math.min(2.5, segmentHeight/4)} fill={isArrangement?"#dbe3ef":"none"} fillOpacity={isArrangement ? .45 : undefined} stroke="#7890B7" strokeWidth="0.28" strokeDasharray="1.35 1.05"/>}
            <text x={segment.x+segment.width/2} y={segmentY+Math.min(3.35,segmentHeight*.62)} textAnchor="middle"
              fontSize={labelSize} fontWeight="700" fill="#334155">{segment.id}</text>
          </g>;
        })}
      </g>;
    })}
  </svg>;
}
