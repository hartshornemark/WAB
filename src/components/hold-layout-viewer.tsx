"use client";
import { useEffect, useId, useRef, useState, useTransition } from "react";
import { aircraftHoldProfile, holdLayoutMirrorsAircraftProfile, holdLayoutPrerequisite, type HoldLayout, holdLayoutX } from "@/domain/hold-layout";
import { aircraftD2HoldId, type AircraftD2Snapshot } from "@/domain/aircraft-d2";
import { lockHoldLayoutCalibration } from "@/app/hold-layout-actions";

type OverlayCalibration={canEdit:boolean;offsetX:number;locked:boolean};
export type HoldLoadOverlay={locationId:string;kind:"BAGGAGE"|"CARGO"|"MAIL";weight:number;occupiedBayIds:string[]};
function uldLoadIdentity(locationId:string){const parts=locationId.split(":");if(parts[0]!=="ULD"||parts.length<5)return null;return{holdId:parts.slice(1,-3).join(":"),positionId:parts.at(-2)!,uldCode:parts.at(-1)!}}
function bulkLoadIdentity(locationId:string){const parts=locationId.split(":");if(parts[0]!=="BLK"||parts.length<3)return null;return{deckCode:parts[1],holdName:parts[2],areaId:parts.length>=5?parts[4]:null}}

export function HoldLayoutViewer({ iata, d2, editing, loads=[], initialConfigurationCode=null, buttonLabel="VIEW HOLD LAYOUT" }: { iata: string; d2: AircraftD2Snapshot; editing: boolean; loads?:HoldLoadOverlay[]; initialConfigurationCode?:string|null; buttonLabel?:string }) {
  const [layout, setLayout] = useState<HoldLayout | null>(null);
  const [calibration,setCalibration]=useState<OverlayCalibration|null>(null);
  const [selectedConfiguration,setSelectedConfiguration]=useState<string|null>(null);
  const [error, setError] = useState("");
  const [pending, setPending] = useState(false);
  const reason = holdLayoutPrerequisite(d2);
  const load=async(configurationCode:string|null)=>{
    setError("");setPending(true);
    try{
      const query=configurationCode?`?fuelConfiguration=${encodeURIComponent(configurationCode)}`:"";
      const response=await fetch(`/api/carrier/${encodeURIComponent(iata)}/aircraft/${encodeURIComponent(d2.typeCode)}/${encodeURIComponent(d2.subtype)}/hold-layout${query}`,{cache:"no-store"});
      const result=await response.json() as {ok:true;layout:HoldLayout;calibration:OverlayCalibration}|{ok:false;error:string};
      if(result.ok){setLayout(result.layout);setCalibration(result.calibration);setSelectedConfiguration(configurationCode)}else setError(result.error);
    }catch{setError("Unable to load the saved hold layout. Check your access and try again.")}finally{setPending(false)}
  };
  if (editing) return null;
  return <div className="hold-layout-control">
    <button type="button" className="secondary" disabled={!!reason||pending} title={reason??undefined} onClick={()=>load(initialConfigurationCode)}>{pending?"Loading layout…":buttonLabel}</button>
    {reason&&<small>{reason}</small>}
    {error&&<small role="alert" className="field-error">{error}</small>}
    {layout&&calibration&&<LayoutDialog key={selectedConfiguration??"ALL"} iata={iata} layout={layout} calibration={calibration} fuelConfigurations={d2.fuelConfigurations??[]} selectedConfiguration={selectedConfiguration} pending={pending} loads={loads} onConfigurationChange={load} onClose={()=>setLayout(null)}/>}
  </div>;
}
function LayoutDialog({iata,layout,calibration,fuelConfigurations,selectedConfiguration,pending,loads,onConfigurationChange,onClose}:{iata:string;layout:HoldLayout;calibration:OverlayCalibration;fuelConfigurations:NonNullable<AircraftD2Snapshot["fuelConfigurations"]>;selectedConfiguration:string|null;pending:boolean;loads:HoldLoadOverlay[];onConfigurationChange:(code:string|null)=>void;onClose:()=>void}){
  const ref=useRef<HTMLDialogElement>(null),titleId=useId();
  const loadedType=(holds:HoldLayout["holds"])=>{
    for(const load of loads){
      const identity=uldLoadIdentity(load.locationId);
      if(!identity)continue;
      const hold=holds.find(item=>aircraftD2HoldId(item)===identity.holdId);
      const position=hold?.uldPositions.find(item=>item.id===identity.positionId&&(!identity.uldCode||item.uldCodes.includes(identity.uldCode)));
      if(position)return position.uldType;
    }
    return undefined;
  };
  const [selectedUldType,setSelectedUldType]=useState<string|null>(()=>loadedType(layout.holds)??layout.uldTypes[0]??null);
  const [deckUldTypes,setDeckUldTypes]=useState<Record<string,string>>(()=>Object.fromEntries(layout.decks.map(deck=>{const holds=layout.holds.filter(hold=>hold.deckCode===deck.code);return[deck.code,loadedType(holds)??holds.flatMap(hold=>hold.uldPositions.map(position=>position.uldType))[0]??""]})));
  const [selectedArrangements,setSelectedArrangements]=useState<Record<string,string>>(()=>Object.fromEntries((layout.uldArrangementSelectors??[]).flatMap(selector=>selector.options[0]?[[`${selector.holdId}\0${selector.uldType}`,selector.options[0].id]]:[])));
  const [offsetX,setOffsetX]=useState(calibration.offsetX),[locked,setLocked]=useState(calibration.locked),[adjusting,setAdjusting]=useState(!calibration.locked),[calibrationError,setCalibrationError]=useState("");
  const [saving,startSaving]=useTransition();
  const arrangementSelectors=(layout.uldArrangementSelectors??[]).filter(selector=>{const hold=layout.holds.find(hold=>aircraftD2HoldId(hold)===selector.holdId);return selector.uldType===(layout.decks.length>1&&hold?deckUldTypes[hold.deckCode]:selectedUldType)});
  const selectedArrangementLabels=arrangementSelectors.flatMap(selector=>{const key=`${selector.holdId}\0${selector.uldType}`;const option=selector.options.find(item=>item.id===selectedArrangements[key]);return option?[option.label]:[]});
  const step=(layout.calibration.armUnit==="IN"?6:.1)*layout.calibration.span/layout.calibration.length;
  const offsetArm=Math.abs(offsetX)*layout.calibration.length/layout.calibration.span;
  const position=offsetX<-.0001?`${offsetArm.toFixed(layout.calibration.armUnit==="IN"?1:2)} ${layout.calibration.armUnit==="IN"?"in":"m"} left`:offsetX>.0001?`${offsetArm.toFixed(layout.calibration.armUnit==="IN"?1:2)} ${layout.calibration.armUnit==="IN"?"in":"m"} right`:"Master position";
  useEffect(()=>{const dialog=ref.current!;dialog.showModal();return()=>dialog.close()},[]);
  return <dialog className="hold-layout-dialog" ref={ref} aria-labelledby={titleId} onCancel={onClose}>
    <header><div><h2 id={titleId}>HOLD LAYOUT</h2><p>{iata} / {layout.typeCode}-{layout.subtype}</p></div><button type="button" className="secondary" onClick={onClose}>CLOSE</button></header>
    <section className="seat-map-calibration" aria-label="Hold-layout alignment">
      <div><strong>OVERLAY POSITION</strong><span className={locked&&!adjusting?"calibration-locked":"calibration-adjusting"}>{locked&&!adjusting?"LOCKED":"ADJUSTING"}</span><small>{position}</small><small>Move the complete hold overlay, then lock the position for this carrier and aircraft type.</small></div>
      {calibration.canEdit&&(adjusting?<div className="seat-map-calibration-actions"><button type="button" className="secondary" onClick={()=>setOffsetX(value=>value-step)}>← SHIFT LEFT</button><button type="button" className="secondary" onClick={()=>setOffsetX(value=>value+step)}>SHIFT RIGHT →</button><button type="button" className="secondary" onClick={()=>setOffsetX(0)}>RESET TO MASTER</button><button type="button" disabled={saving} onClick={()=>{setCalibrationError("");startSaving(async()=>{const result=await lockHoldLayoutCalibration(iata,layout.typeCode,layout.subtype,offsetX);if(result.ok){setLocked(true);setAdjusting(false);}else setCalibrationError(result.error);});}}>{saving?"LOCKING…":"LOCK POSITION"}</button></div>:<button type="button" className="secondary" onClick={()=>{setLocked(false);setAdjusting(true);}}>ADJUST POSITION</button>)}
      {calibrationError&&<small className="field-error" role="alert">{calibrationError}</small>}
    </section>
    {fuelConfigurations.length>0&&<nav className="hold-layout-uld-selectors hold-layout-fuel-selectors" aria-label="Fitted fuel configuration"><span>FITTED CONFIGURATION</span><button type="button" disabled={pending} className={selectedConfiguration===null?"selected":""} aria-pressed={selectedConfiguration===null} onClick={()=>onConfigurationChange(null)}>ALL</button>{fuelConfigurations.map(option=><button type="button" disabled={pending} className={selectedConfiguration===option.code?"selected":""} aria-pressed={selectedConfiguration===option.code} key={option.code} onClick={()=>onConfigurationChange(option.code)}>{option.code}</button>)}</nav>}
    {layout.decks.length===1&&layout.uldTypes.length>0&&<nav className="hold-layout-uld-selectors" aria-label="ULD bay type"><span>ULD BAY TYPE</span>{layout.uldTypes.map(type=><button type="button" className={selectedUldType===type?"selected":""} aria-pressed={selectedUldType===type} key={type} onClick={()=>setSelectedUldType(type)}>{type}</button>)}</nav>}
    {arrangementSelectors.map(selector=>{const key=`${selector.holdId}\0${selector.uldType}`;return <nav className="hold-layout-uld-selectors hold-layout-arrangement-selectors" aria-label={selector.label} key={key}><span>{selector.label}</span>{selector.options.map(option=><button type="button" className={selectedArrangements[key]===option.id?"selected":""} aria-pressed={selectedArrangements[key]===option.id} key={option.id} onClick={()=>setSelectedArrangements(current=>({...current,[key]:option.id}))}>{option.label}</button>)}</nav>})}
    {layout.decks.map(deck=>{const types=[...new Set(layout.holds.filter(hold=>hold.deckCode===deck.code).flatMap(hold=>hold.uldPositions.map(position=>position.uldType)))].sort();const selected=layout.decks.length>1?deckUldTypes[deck.code]||null:selectedUldType;return <section key={deck.code} className="hold-layout-deck"><h3>{deck.name}</h3>{layout.decks.length>1&&types.length>0&&<nav className="hold-layout-uld-selectors" aria-label={`${deck.name} ULD bay type`}><span>ULD BAY TYPE</span>{types.map(type=><button type="button" className={selected===type?"selected":""} aria-pressed={selected===type} key={type} onClick={()=>setDeckUldTypes(current=>({...current,[deck.code]:type}))}>{type}</button>)}</nav>}<HoldDiagram layout={layout} deckCode={deck.code} selectedUldType={selected} selectedArrangements={selectedArrangements} offsetX={offsetX} loads={loads}/></section>})}
    {layout.boundaryNotes?.map(note=><p className="hold-layout-caption" key={note}>{note}</p>)}
    <p className="hold-layout-caption">Tail Left · Nose Right. {selectedConfiguration&&`Showing the ${selectedConfiguration} fitted configuration. `}{layout.decks.length===1&&selectedUldType&&`Showing ${selectedUldType} loading positions only. `}{selectedArrangementLabels.length>0&&`Selected arrangement: ${selectedArrangementLabels.join("; ")}. `}{layout.usesGlobalHoldBoundaries?"Hold lengths use the global aircraft-type boundaries where optional carrier boundaries are absent.":"Positions use saved carrier Balance Arms."} {layout.calibration.diagramCaption??"Aircraft doors are shown in the official plan. Hold widths are schematic."}</p>
  </dialog>;
}
export function HoldDiagram({ layout, deckCode, selectedUldType, selectedArrangements, offsetX, loads, fillAirframe=false }: { layout: HoldLayout; deckCode: string; selectedUldType:string|null; selectedArrangements:Record<string,string>; offsetX:number; loads:HoldLoadOverlay[]; fillAirframe?:boolean }) {
  const [imageFailed,setImageFailed]=useState(false);
  if(imageFailed)return <p role="alert" className="field-error">The aircraft outline could not be loaded. Close this view and open it again to retry.</p>;
  const aircraft = layout.calibration;
  const holds = layout.holds.filter(h => h.deckCode === deckCode);
  const viewWidth = aircraft.imageFrame.width, viewHeight = aircraft.imageFrame.height;
  const viewX = aircraft.tailX - aircraft.span / 2 - viewWidth / 2;
  const viewY = aircraft.centreY - viewHeight / 2;
  const image = aircraft.imageFrame;
  const profileTransform=holdLayoutMirrorsAircraftProfile(aircraft)?`translate(${2*image.x+image.width} 0) scale(-1 1)`:undefined;
  const bodyTop=aircraft.centreY-image.height*.115,bodyBottom=aircraft.centreY+image.height*.115;
  const px=(fraction:number)=>image.x+image.width*fraction,py=(fraction:number)=>image.y+image.height*fraction;
  return <svg className="hold-layout-svg" viewBox={`${viewX} ${viewY} ${viewWidth} ${viewHeight}`} role="img" aria-label={`${deckCode}: ${holds.map(h => `Hold ${h.name}`).join("; ")}`}>
    {fillAirframe&&<g className="hold-layout-airframe-fill" aria-hidden="true">
      <path d={`M ${px(.012)} ${aircraft.centreY} C ${px(.035)} ${bodyTop}, ${px(.12)} ${bodyTop}, ${px(.25)} ${bodyTop} L ${px(.88)} ${bodyTop} C ${px(.945)} ${bodyTop}, ${px(.982)} ${py(.42)}, ${px(.992)} ${aircraft.centreY} C ${px(.982)} ${py(.58)}, ${px(.945)} ${bodyBottom}, ${px(.88)} ${bodyBottom} L ${px(.25)} ${bodyBottom} C ${px(.12)} ${bodyBottom}, ${px(.035)} ${bodyBottom}, ${px(.012)} ${aircraft.centreY} Z`}/>
      <path d={`M ${px(.43)} ${bodyTop} L ${px(.385)} ${py(.025)} L ${px(.485)} ${py(.025)} L ${px(.575)} ${bodyTop} Z`}/><path d={`M ${px(.43)} ${bodyBottom} L ${px(.385)} ${py(.975)} L ${px(.485)} ${py(.975)} L ${px(.575)} ${bodyBottom} Z`}/>
      <path d={`M ${px(.105)} ${bodyTop} L ${px(.045)} ${py(.08)} L ${px(.105)} ${py(.08)} L ${px(.185)} ${bodyTop} Z`}/><path d={`M ${px(.105)} ${bodyBottom} L ${px(.045)} ${py(.92)} L ${px(.105)} ${py(.92)} L ${px(.185)} ${bodyBottom} Z`}/>
    </g>}
    <image className="hold-layout-airframe" transform={profileTransform} onError={()=>setImageFailed(true)} href={aircraft.asset} x={image.x} y={image.y} width={image.width} height={image.height}/>
    <g transform={`translate(${offsetX} 0)`}>{holds.map(hold => {
      const individualProfile=aircraftHoldProfile(aircraft,hold);
      const profile=individualProfile??aircraft.combinedHoldProfile;
      if(profile && hold.holdType==="BLK") {
        const holdLoad=loads.find(item=>{const identity=bulkLoadIdentity(item.locationId);return identity?.deckCode===hold.deckCode&&identity.holdName===hold.name&&identity.areaId===null});
        const commodity=holdLoad?.kind==="BAGGAGE"?"B":holdLoad?.kind==="CARGO"?"C":holdLoad?.kind==="MAIL"?"M":"";
        const joinArm=individualProfile?undefined:aircraft.combinedHoldProfile?.joinArm;
        const halfAt=(arm:number)=>{const points=profile.points;const next=points.findIndex(p=>p.arm>=arm);if(next<0)return points[points.length-1].halfWidth;if(next===0)return points[0].halfWidth;const a=points[next-1],b=points[next];return a.halfWidth+(b.halfWidth-a.halfWidth)*(arm-a.arm)/(b.arm-a.arm)};
        const from=hold.balanceFrom!,to=hold.balanceTo!;
        const profileOffsetX=hold.x-holdLayoutX(to,aircraft);
        const profileX=(arm:number)=>holdLayoutX(arm,aircraft)+profileOffsetX;
        const stations=[from,...profile.points.filter(p=>p.arm>from&&p.arm<to).map(p=>p.arm),to];
        const points=[...stations.map(arm=>`${profileX(arm)},${aircraft.centreY-halfAt(arm)}`),...stations.toReversed().map(arm=>`${profileX(arm)},${aircraft.centreY+halfAt(arm)}`)].join(" ");
        const labels=hold.subdivisions;
        const forward=labels.at(-1)?.id??hold.name,aft=labels[0]?.id??hold.name;
        return <g key={hold.name}><title>Hold {hold.name}; stations {from}–{to} {aircraft.armUnit??"M"}</title>
          <polygon points={points} fill={holdLoad?"#747b86":"#edf1f6"} fillOpacity={holdLoad ? .82 : .5} stroke={holdLoad?"#424852":"#939393"} strokeWidth={holdLoad ? .4 : .32}/>
          {joinArm!==undefined&&joinArm>from&&joinArm<to&&<path d={`M ${profileX(joinArm)} ${aircraft.centreY-halfAt(joinArm)} V ${aircraft.centreY+halfAt(joinArm)}`} stroke="#7890B7" strokeWidth="0.28" strokeDasharray="1.35 1.05"><title>Indicative join at station {joinArm}; not a confirmed compartment boundary</title></path>}
          <text x={hold.x+hold.width-1.15} y={aircraft.centreY-halfAt(from)+3.7} textAnchor="end" fontSize="2.5" fontWeight="700" fill="#334155">{forward}</text>
          {labels.length>1&&<text x={hold.x+1.15} y={aircraft.centreY-halfAt(to)+3.7} textAnchor="start" fontSize="2.5" fontWeight="700" fill="#334155">{aft}</text>}
          {holdLoad&&<><text x={hold.x+hold.width/2} y={aircraft.centreY-.3} textAnchor="middle" fontSize="2.7" fontWeight="800" fill="#fff">{commodity}</text><text x={hold.x+hold.width/2} y={aircraft.centreY+2.4} textAnchor="middle" fontSize="2" fontWeight="700" fill="#fff">{Math.round(holdLoad.weight)}</text></>}
        </g>;
      }
      const selector=(layout.uldArrangementSelectors??[]).find(item=>item.holdId===aircraftD2HoldId(hold)&&item.uldType===selectedUldType);
      const selectedOption=selector?.options.find(option=>option.id===selectedArrangements[`${selector.holdId}\0${selector.uldType}`]);
      const selectedPositions=selectedUldType?hold.uldPositions.filter(position=>position.uldType===selectedUldType
        &&(!selectedOption||selectedOption.includedPositionIds.includes(position.id))&&!selectedOption?.excludedPositionIds.includes(position.id)).map(position=>{
          const codeRange=selectedOption?.uldCode?position.codeRanges?.find(range=>range.uldCode===selectedOption.uldCode):undefined;
          if(codeRange)return{...position,x:codeRange.x,width:codeRange.width,uldCodes:[codeRange.uldCode]};
          return selectedOption&&position.sourceX!==undefined&&position.sourceWidth!==undefined?{...position,x:position.sourceX,width:position.sourceWidth}:position;
        }):[];
      const completeHoldLoad=loads.find(item=>{const identity=bulkLoadIdentity(item.locationId);return identity?.deckCode===hold.deckCode&&identity.holdName===hold.name&&identity.areaId===null});
      const completeHoldCommodity=completeHoldLoad?.kind==="BAGGAGE"?"B":completeHoldLoad?.kind==="CARGO"?"C":completeHoldLoad?.kind==="MAIL"?"M":"";
      return <g key={hold.name}><title>Hold {hold.name}; Balance Arm {hold.balanceFrom!.toFixed(3)}–{hold.balanceTo!.toFixed(3)} {aircraft.armUnit??"M"}{completeHoldLoad?`; ${completeHoldLoad.kind} ${completeHoldLoad.weight}`:""}</title>
        <rect x={hold.x} y={aircraft.holdY} width={hold.width} height={aircraft.holdHeight} rx={Math.min(6.2, aircraft.holdHeight/4)} fill={completeHoldLoad?"#747b86":"none"} fillOpacity={completeHoldLoad ? .82 : undefined} stroke={completeHoldLoad?"#424852":"#939393"} strokeWidth={completeHoldLoad ? .4 : .32}/>
        {completeHoldLoad&&<><text x={hold.x+hold.width/2} y={aircraft.holdY+aircraft.holdHeight*.43} textAnchor="middle" fontSize={Math.max(1.25,Math.min(3,aircraft.holdHeight*.34))} fontWeight="800" fill="#fff">{completeHoldCommodity}</text><text x={hold.x+hold.width/2} y={aircraft.holdY+aircraft.holdHeight*.76} textAnchor="middle" fontSize={Math.max(1,Math.min(2.2,aircraft.holdHeight*.25))} fontWeight="700" fill="#fff">{Math.round(completeHoldLoad.weight)}</text></>}
        {selectedOption?.referencePosition&&<g><title>{selectedOption.label}; {selectedOption.referencePosition.uldCodes.join(", ")} at {selectedOption.referencePosition.id}</title>
          <rect x={selectedOption.referencePosition.x+.35} y={aircraft.holdY+.35} width={Math.max(0,selectedOption.referencePosition.width-.7)} height={aircraft.holdHeight-.7}
            rx={Math.min(2.5,aircraft.holdHeight/4)} fill="#f2d7a1" fillOpacity=".38" stroke="#a47724" strokeWidth=".32"/>
          <text x={selectedOption.referencePosition.x+selectedOption.referencePosition.width/2} y={aircraft.holdY+aircraft.holdHeight/2+.8} textAnchor="middle" fontSize="2.15" fontWeight="700" fill="#71501d">{selectedOption.referencePosition.id}</text>
        </g>}
        {(selectedUldType&&hold.holdType==="ULD"?selectedPositions:hold.subdivisions).map(segment => {
          const isArrangement=!("kind" in segment);
          const label=isArrangement?`${segment.uldType} position`:(segment.kind === "BAY" ? "Bay" : segment.kind === "AREA" ? "Area" : segment.kind === "COMPARTMENT" ? "Compartment" : "Hold");
          const holdId=aircraftD2HoldId(hold);
          const load=loads.find(item=>{const uld=uldLoadIdentity(item.locationId);if(uld)return uld.holdId===holdId&&(uld.positionId===segment.id||item.occupiedBayIds.includes(segment.id));const bulk=bulkLoadIdentity(item.locationId);return bulk?.deckCode===hold.deckCode&&bulk.holdName===hold.name&&bulk.areaId===segment.id});
          const commodity=load?.kind==="BAGGAGE"?"B":load?.kind==="CARGO"?"C":load?.kind==="MAIL"?"M":"";
          const side=isArrangement?(segment.id.trim().toUpperCase().endsWith("L")?"L":segment.id.trim().toUpperCase().endsWith("R")?"R":"FULL"):"FULL";
          const inset=.35,gap=.18,availableHeight=aircraft.holdHeight-inset*2;
          const segmentY=side==="L"?aircraft.holdY+inset:side==="R"?aircraft.holdY+inset+availableHeight/2+gap/2:aircraft.holdY+inset;
          const segmentHeight=side==="FULL"?availableHeight:availableHeight/2-gap/2;
          const labelSize=Math.max(1.05,Math.min(2.5,(segment.width-1)/(Math.max(1,segment.id.length)*.64)));
          return <g key={`${isArrangement?segment.uldType:segment.kind}-${segment.compartmentId}-${segment.id}`}>
            <title>{label} {segment.id}{isArrangement&&segment.uldCodes.length?`; ${segment.uldCodes.join(", ")}`:""}{load?`; ${load.kind} ${load.weight}`:""}</title>
            {(isArrangement||segment.kind !== "HOLD") && <rect x={segment.x + inset} y={segmentY} width={Math.max(0, segment.width - inset*2)} height={segmentHeight}
              rx={Math.min(2.5, segmentHeight/4)} fill={load?"#747b86":isArrangement?"#dbe3ef":"none"} fillOpacity={load ? .82 : isArrangement ? .45 : undefined} stroke={load?"#424852":"#7890B7"} strokeWidth={load ? .4 : .28} strokeDasharray={load?undefined:"1.35 1.05"}/>}
            {load?<><text x={segment.x+segment.width/2} y={segmentY+segmentHeight*.43} textAnchor="middle" fontSize={Math.max(1.25,Math.min(3,segmentHeight*.34))} fontWeight="800" fill="#fff">{commodity}</text><text x={segment.x+segment.width/2} y={segmentY+segmentHeight*.76} textAnchor="middle" fontSize={Math.max(1,Math.min(2.2,segmentHeight*.25))} fontWeight="700" fill="#fff">{Math.round(load.weight)}</text></>:<text x={segment.x+segment.width/2} y={segmentY+Math.min(3.35,segmentHeight*.62)} textAnchor="middle" fontSize={labelSize} fontWeight="700" fill="#334155">{segment.id}</text>}
          </g>;
        })}
      </g>;
    })}</g>
  </svg>;
}
