"use client";
import { useEffect, useId, useRef, useState, useTransition } from "react";
import { loadSeatMap,lockSeatMapCalibration } from "@/app/seat-map-actions";
import { seatMapDrawingScale, seatMapMirrorsAircraftProfile, seatMapUnavailable, seatMapSeatDepth, seatMapOverlaps, seatMapGroupSlots, seatMapGroupContentStarts, type SeatMap, type SeatMapArea, type SeatMapRow } from "@/domain/seat-map";
import type { AircraftD8Snapshot } from "@/domain/aircraft-d8";

const colours=["#444444","#777777","#AAAAAA","#D0D0D0"];
type MapChoice={code:string;description:string;layout:SeatMap|null;error:string|null};
type MapCalibration={canEdit:boolean;offsetX:number;locked:boolean};
export type SeatMapPassengerLoad={male:number;female:number;child:number;infant:number};
export function OperationalCabinOverlay({iata,typeCode,subtype,configurationCode,areas}:{iata:string;typeCode:string;subtype:string;configurationCode:string|null;areas:Array<{areaId:string;passengers:number}>}){
 const[loaded,setLoaded]=useState<{choices:MapChoice[];calibration:MapCalibration}|null>(null),[error,setError]=useState(""),[pending,start]=useTransition();
 useEffect(()=>{let current=true;start(async()=>{const result=await loadSeatMap(iata,typeCode,subtype);if(!current)return;if(result.ok)setLoaded({choices:result.layouts,calibration:result.calibration});else setError(result.error)});return()=>{current=false}},[iata,subtype,typeCode]);
 const selected=loaded?.choices.find(choice=>choice.code===configurationCode)??loaded?.choices[0],layout=selected?.layout,passengerLoads=Object.fromEntries(areas.map(area=>[area.areaId,{male:area.passengers,female:0,child:0,infant:0}]));
 if(pending&&!loaded)return <p className="load-control-notice">Loading the calibrated cabin overlay…</p>;
 if(error)return <p className="load-control-notice warning">{error}</p>;
 if(selected?.error)return <p className="load-control-notice warning">{selected.error}</p>;
 if(!layout)return <p className="load-control-notice warning">No calibrated cabin drawing is available for this configuration.</p>;
 return <section className="operational-cabin-overlay"><header><div><p className="eyebrow">CABIN LOAD</p><h4>Booked passenger forecast</h4></div><div><strong>{areas.reduce((sum,area)=>sum+area.passengers,0).toLocaleString()} PAX</strong><span>AREA-PROPORTIONAL FORECAST</span>{selected.code&&<small>CONFIGURATION {selected.code}</small>}</div></header><SeatDiagram layout={layout} rows={layout.decks.flatMap(deck=>deck.rows)} areas={layout.decks.flatMap(deck=>deck.areas)} areaIds={[...new Set(layout.decks.flatMap(deck=>deck.rows.map(row=>row.areaId)))]} previewShift={loaded!.calibration.offsetX} passengerLoads={passengerLoads}/><p>Tail left · Nose right. The current view distributes booked passengers by cabin area; check-in integration can replace this with live area, row or individual-seat occupancy.</p></section>;
}
export function SeatMapViewer({iata,snapshot,configurationCode,passengerLoads,buttonLabel="VIEW SEAT MAP"}:{iata:string;snapshot:AircraftD8Snapshot;configurationCode?:string;passengerLoads?:Record<string,SeatMapPassengerLoad>;buttonLabel?:string}) {
  const [loaded,setLoaded]=useState<{choices:MapChoice[];calibration:MapCalibration}|null>(null),[error,setError]=useState(""),[pending,start]=useTransition();
  const reason=seatMapUnavailable(snapshot);
  return <div className="hold-layout-control">
    <button className="secondary" type="button" disabled={!!reason||pending} title={reason??"View saved D8 rows"} onClick={()=>{setError("");start(async()=>{
      const result=await loadSeatMap(iata,snapshot.typeCode,snapshot.subtype);
      if(result.ok)setLoaded({choices:result.layouts,calibration:result.calibration});else setError(result.error);
    });}}>{pending?"Loading seat map…":buttonLabel}</button>
    {reason&&<small>{reason}</small>}{error&&<small className="field-error" role="alert">{error}</small>}
    {loaded&&<SeatMapDialog iata={iata} choices={loaded.choices} calibration={loaded.calibration} initialCode={configurationCode} passengerLoads={passengerLoads} onClose={()=>setLoaded(null)}/>}
  </div>;
}
function SeatMapDialog({iata,choices,calibration,initialCode,passengerLoads,onClose}:{iata:string;choices:MapChoice[];calibration:MapCalibration;initialCode?:string;passengerLoads?:Record<string,SeatMapPassengerLoad>;onClose:()=>void}) {
  const [code,setCode]=useState(initialCode??choices[0]?.code??"");
  const [offsetX,setOffsetX]=useState(calibration.offsetX),[locked,setLocked]=useState(calibration.locked),[adjusting,setAdjusting]=useState(!calibration.locked),[calibrationError,setCalibrationError]=useState("");
  const [saving,startSaving]=useTransition();
  const selected=choices.find(choice=>choice.code===code)??choices[0];
  const layout=selected?.layout;
  const ref=useRef<HTMLDialogElement>(null),title=useId();
  useEffect(()=>{const dialog=ref.current!;dialog.showModal();return()=>dialog.close();},[]);
  const areaIds=[...new Set((layout?.decks??[]).flatMap(d=>d.rows.map(r=>r.areaId)))];
  const step=layout?(layout.calibration.armUnit==="IN"?6:.1)*layout.calibration.span/layout.calibration.length:1;
  const offsetArm=layout?Math.abs(offsetX)*layout.calibration.length/layout.calibration.span:0;
  const position=offsetX<-.0001?`${offsetArm.toFixed(layout?.calibration.armUnit==="IN"?1:2)} ${layout?.calibration.armUnit==="IN"?"in":"m"} left`:offsetX>.0001?`${offsetArm.toFixed(layout?.calibration.armUnit==="IN"?1:2)} ${layout?.calibration.armUnit==="IN"?"in":"m"} right`:"Master position";
  return <dialog ref={ref} className="hold-layout-dialog seat-map-dialog" aria-labelledby={title} onCancel={onClose}>
    <header><div><h2 id={title}>SEAT MAP</h2><p>{iata} / {layout?.typeCode}-{layout?.subtype} · {layout?.decks.reduce((n,d)=>n+d.rows.reduce((s,r)=>s+r.seats,0),0)} usable seats · {selected.code?`Configuration ${selected.code} — ${selected.description}`:"Physical layout (D8)"}</p></div><button className="secondary" onClick={onClose}>CLOSE</button></header>
    {choices.length>1&&<div className="d9-selectors seat-map-config" role="group" aria-label="Configuration">{choices.map(choice=><button type="button" key={choice.code} className={selected.code===choice.code?"selected":""} aria-pressed={selected.code===choice.code} onClick={()=>setCode(choice.code)}><strong>{choice.code}</strong><span>{choice.description}</span></button>)}</div>}
    {layout&&<section className="seat-map-calibration" aria-label="Seat-map alignment">
      <div><strong>OVERLAY POSITION</strong><span className={locked&&!adjusting?"calibration-locked":"calibration-adjusting"}>{locked&&!adjusting?"LOCKED":"ADJUSTING"}</span><small>{position}</small><small>Move the complete seat overlay, then lock the position for this carrier and aircraft type.</small></div>
      {calibration.canEdit&&(adjusting?<div className="seat-map-calibration-actions"><button type="button" className="secondary" onClick={()=>setOffsetX(value=>value-step)}>← SHIFT LEFT</button><button type="button" className="secondary" onClick={()=>setOffsetX(value=>value+step)}>SHIFT RIGHT →</button><button type="button" className="secondary" onClick={()=>setOffsetX(0)}>RESET TO MASTER</button><button type="button" disabled={saving} onClick={()=>{setCalibrationError("");startSaving(async()=>{const result=await lockSeatMapCalibration(iata,layout.typeCode,layout.subtype,offsetX);if(result.ok){setLocked(true);setAdjusting(false);}else setCalibrationError(result.error);});}}>{saving?"LOCKING…":"LOCK POSITION"}</button></div>:<button type="button" className="secondary" onClick={()=>{setLocked(false);setAdjusting(true);}}>ADJUST POSITION</button>)}
      {calibrationError&&<small className="field-error" role="alert">{calibrationError}</small>}
    </section>}
    {selected.error&&<p className="field-error" role="alert">{selected.error}</p>}
    {layout&&layout.decks.map(deck=><section className="hold-layout-deck" key={deck.code}>{layout.decks.length>1&&<h3>{deck.code==="MAIN"?"Main Deck":deck.code==="UPPER"?"Upper Deck":`Deck ${deck.code}`}</h3>}<SeatDiagram layout={layout} rows={deck.rows} areas={deck.areas} areaIds={areaIds} previewShift={offsetX} passengerLoads={passengerLoads}/></section>)}
    <p className="hold-layout-caption">Tail Left · Nose Right. Rows use the balance arms calculated from C4 and D8. Seat groups run from top to bottom (left to right facing the nose). Crossed seats are blocked and excluded from the usable seat total. Seat sizes and aisle widths are schematic; row labels identify rows, not individual seats.{layout?.calibration.seatMapCaption&&<> {layout.calibration.seatMapCaption}</>}</p>
  </dialog>;
}
export function SeatDiagram({layout,rows,areas,areaIds,previewShift,passengerLoads}:{layout:SeatMap;rows:SeatMapRow[];areas:SeatMapArea[];areaIds:string[];previewShift:number;passengerLoads?:Record<string,SeatMapPassengerLoad>}) {
  const [imageFailed,setImageFailed]=useState(false);
  if(imageFailed)return <p role="alert" className="field-error">The aircraft outline could not be loaded. Close this view and open it again to retry.</p>;
  const aircraft=layout.calibration,image=aircraft.imageFrame;
  const width=image.width,height=image.height,viewX=aircraft.tailX-aircraft.span/2-width/2,viewY=aircraft.centreY-height/2;
  const drawingScale=seatMapDrawingScale(aircraft),aisle=1.8*drawingScale,gap=.35*drawingScale,cabinWidth=17*drawingScale;
  const slots=(row:SeatMapRow)=>seatMapGroupSlots(row.groups,rows.map(r=>r.groups));
  const physicalSeats=(row:SeatMapRow)=>slots(row).reduce((sum,n)=>sum+n,0);
  const seatWidth=Math.min(...rows.map(row=>(cabinWidth-(row.groups.length-1)*aisle-(physicalSeats(row)-row.groups.length)*gap)/physicalSeats(row)));
  const depth=seatMapSeatDepth(rows,drawingScale),overlaps=seatMapOverlaps(rows,depth);
  const profileTransform=seatMapMirrorsAircraftProfile(aircraft)?`translate(${2*image.x+image.width} 0) scale(-1 1)`:undefined;
  const previewDelta=previewShift-layout.longitudinalShift;
  const loadedAreas=passengerLoads?areas.map(area=>({area,load:passengerLoads[area.id]})).filter((item):item is{area:SeatMapArea;load:SeatMapPassengerLoad}=>!!item.load).sort((a,b)=>(a.area.x+previewDelta)-(b.area.x+previewDelta)):[];
  return <>{overlaps.length>0&&<p className="field-error" role="status">Check D8 row positions: {overlaps.map(pair=>pair.join(" and ")).join("; ")}. These rows overlap at their saved balance arms.</p>}{loadedAreas.length>0&&<div className="seat-map-load-summary" aria-label="Passenger load by cabin area">{loadedAreas.map(({area,load})=><div key={area.id}><strong>{area.id}</strong><span>{load.male+load.female+load.child+load.infant} PAX</span></div>)}</div>}<svg className="hold-layout-svg seat-map-svg" viewBox={`${viewX} ${viewY} ${width} ${height}`} role="img" aria-label={`Seat map: ${rows.map(r=>`Row ${r.rowNumber}, ${r.groups.join("-")} seats`).join("; ")}`}>
    <image transform={profileTransform} onError={()=>setImageFailed(true)} href={aircraft.asset} x={image.x} y={image.y} width={image.width} height={image.height}/>
    {areas.map(area=>{const load=passengerLoads?.[area.id],total=load?load.male+load.female+load.child+load.infant:0;return <g key={area.id}><title>Cabin Area {area.id} · Centroid {area.centroid.toFixed(3)} {aircraft.armUnit==="IN"?"in":"m"}{load?` · ${total} passengers`:""}</title><text x={area.x+previewDelta} y={aircraft.centreY-19*drawingScale} textAnchor="middle" fontSize={2.35*drawingScale} fontWeight="700" fill="#555">{area.id}</text><line x1={area.x+previewDelta-3*drawingScale} x2={area.x+previewDelta+3*drawingScale} y1={aircraft.centreY-17.5*drawingScale} y2={aircraft.centreY-17.5*drawingScale} stroke={colours[areaIds.indexOf(area.id)%colours.length]} strokeWidth={.8*drawingScale}/></g>})}
    {rows.map(row=>{
      const colour=colours[areaIds.indexOf(row.areaId)%colours.length];
      const rowSlots=slots(row),starts=seatMapGroupContentStarts(row.groups,rowSlots,seatWidth,aisle,gap);
      return <g key={row.rowNumber}><title>Cabin Area {row.areaId} · Row {row.rowNumber} · {row.groups.join("-")} · Balance Arm {row.centroid.toFixed(3)} {aircraft.armUnit==="IN"?"in":"m"}</title>
        {row.groups.flatMap((count,group)=>Array.from({length:count},(_,seat)=>{
          const seatY=aircraft.centreY+starts[group]+seat*(seatWidth+gap),seatX=row.x+previewDelta;
          if(row.blockedCentres&&seat===1)return <g key={`${group}-${seat}`}><title>Blocked centre seat — unavailable</title><rect x={seatX-depth/2} y={seatY} width={depth} height={seatWidth} rx={.35*drawingScale} fill="#F4F4F4" stroke="#777" strokeWidth={.22*drawingScale}/><path d={`M ${seatX-depth/2+.2*drawingScale} ${seatY+.2*drawingScale} L ${seatX+depth/2-.2*drawingScale} ${seatY+seatWidth-.2*drawingScale} M ${seatX+depth/2-.2*drawingScale} ${seatY+.2*drawingScale} L ${seatX-depth/2+.2*drawingScale} ${seatY+seatWidth-.2*drawingScale}`} stroke="#555" strokeWidth={.25*drawingScale}/></g>;
          return <g key={`${group}-${seat}`}><rect x={seatX-depth/2} y={seatY} width={depth} height={seatWidth} rx={.35*drawingScale} fill={colour} fillOpacity=".95" stroke="#444444" strokeWidth={.22*drawingScale}/><path d={`M ${seatX-depth/2+.4*drawingScale} ${seatY+.25*drawingScale} v ${Math.max(0,seatWidth-.5*drawingScale)}`} stroke={colour==="#444444"?"#EEEEEE":"#444444"} strokeWidth={.35*drawingScale}/></g>;
        }))}
        <text x={row.x+previewDelta} y={aircraft.centreY+18.5*drawingScale} textAnchor="middle" fontSize={2.2*drawingScale} fontWeight="700" fill="#444444">{row.rowNumber}</text>
      </g>;
    })}
  </svg></>;
}
