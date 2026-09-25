"use client";
import { useEffect, useId, useRef, useState, useTransition } from "react";
import { loadSeatMap } from "@/app/seat-map-actions";
import { seatMapUnavailable, seatMapSeatDepth, seatMapOverlaps, seatMapGroupSlots, seatMapGroupStarts, type SeatMap, type SeatMapArea, type SeatMapRow } from "@/domain/seat-map";
import type { AircraftD8Snapshot } from "@/domain/aircraft-d8";

const colours=["#444444","#777777","#AAAAAA","#D0D0D0"];
type MapChoice={code:string;description:string;layout:SeatMap|null;error:string|null};
export function SeatMapViewer({iata,snapshot,configurationCode}:{iata:string;snapshot:AircraftD8Snapshot;configurationCode?:string}) {
  const [choices,setChoices]=useState<MapChoice[]|null>(null),[error,setError]=useState(""),[pending,start]=useTransition();
  const reason=seatMapUnavailable(snapshot);
  return <div className="hold-layout-control">
    <button className="secondary" type="button" disabled={!!reason||pending} title={reason??"View saved D8 rows"} onClick={()=>{setError("");start(async()=>{
      const result=await loadSeatMap(iata,snapshot.typeCode,snapshot.subtype);
      if(result.ok)setChoices(result.layouts);else setError(result.error);
    });}}>{pending?"Loading seat map…":"VIEW SEAT MAP"}</button>
    {reason&&<small>{reason}</small>}{error&&<small className="field-error" role="alert">{error}</small>}
    {choices&&<SeatMapDialog iata={iata} choices={choices} initialCode={configurationCode} onClose={()=>setChoices(null)}/>}
  </div>;
}
function SeatMapDialog({iata,choices,initialCode,onClose}:{iata:string;choices:MapChoice[];initialCode?:string;onClose:()=>void}) {
  const [code,setCode]=useState(initialCode??choices[0]?.code??"");
  const selected=choices.find(choice=>choice.code===code)??choices[0];
  const layout=selected?.layout;
  const ref=useRef<HTMLDialogElement>(null),title=useId();
  useEffect(()=>{const dialog=ref.current!;dialog.showModal();return()=>dialog.close();},[]);
  const areaIds=[...new Set((layout?.decks??[]).flatMap(d=>d.rows.map(r=>r.areaId)))];
  return <dialog ref={ref} className="hold-layout-dialog seat-map-dialog" aria-labelledby={title} onCancel={onClose}>
    <header><div><h2 id={title}>SEAT MAP</h2><p>{iata} / {layout?.typeCode}-{layout?.subtype} · {layout?.decks.reduce((n,d)=>n+d.rows.reduce((s,r)=>s+r.seats,0),0)} usable seats · {selected.code?`Configuration ${selected.code} — ${selected.description}`:"Physical layout (D8)"}</p></div><button className="secondary" onClick={onClose}>CLOSE</button></header>
    {choices.length>1&&<div className="d9-selectors seat-map-config" role="group" aria-label="Configuration">{choices.map(choice=><button type="button" key={choice.code} className={selected.code===choice.code?"selected":""} aria-pressed={selected.code===choice.code} onClick={()=>setCode(choice.code)}><strong>{choice.code}</strong><span>{choice.description}</span></button>)}</div>}
    {selected.error&&<p className="field-error" role="alert">{selected.error}</p>}
    {layout&&layout.decks.map(deck=><section className="hold-layout-deck" key={deck.code}>{layout.decks.length>1&&<h3>{deck.code==="MAIN"?"Main Deck":deck.code==="UPPER"?"Upper Deck":`Deck ${deck.code}`}</h3>}<SeatDiagram layout={layout} rows={deck.rows} areas={deck.areas} areaIds={areaIds}/></section>)}
    <p className="hold-layout-caption">Tail Left · Nose Right. Rows use the balance arms calculated from C4 and D8. Seat groups run from top to bottom (left to right facing the nose). Crossed seats are blocked and excluded from the usable seat total. Seat sizes and aisle widths are schematic; row labels identify rows, not individual seats.</p>
  </dialog>;
}
function SeatDiagram({layout,rows,areas,areaIds}:{layout:SeatMap;rows:SeatMapRow[];areas:SeatMapArea[];areaIds:string[]}) {
  const [imageFailed,setImageFailed]=useState(false);
  if(imageFailed)return <p role="alert" className="field-error">The aircraft outline could not be loaded. Close this view and open it again to retry.</p>;
  const aircraft=layout.calibration,image=aircraft.imageFrame;
  const width=image.width,height=image.height,viewX=aircraft.tailX-aircraft.span/2-width/2,viewY=aircraft.centreY-height/2;
  const aisle=1.8,gap=.35;
  const slots=(row:SeatMapRow)=>seatMapGroupSlots(row.groups,rows.map(r=>r.groups));
  const physicalSeats=(row:SeatMapRow)=>slots(row).reduce((sum,n)=>sum+n,0);
  const seatWidth=Math.min(...rows.map(row=>(17-(row.groups.length-1)*aisle-(physicalSeats(row)-row.groups.length)*gap)/physicalSeats(row)));
  const depth=seatMapSeatDepth(rows),overlaps=seatMapOverlaps(rows,depth);
  return <>{overlaps.length>0&&<p className="field-error" role="status">Check D8 row positions: {overlaps.map(pair=>pair.join(" and ")).join("; ")}. These rows overlap at their saved balance arms.</p>}<svg className="hold-layout-svg seat-map-svg" viewBox={`${viewX} ${viewY} ${width} ${height}`} role="img" aria-label={`Seat map: ${rows.map(r=>`Row ${r.rowNumber}, ${r.groups.join("-")} seats`).join("; ")}`}>
    <image onError={()=>setImageFailed(true)} href={aircraft.asset} x={image.x} y={image.y} width={image.width} height={image.height}/>
    {areas.map(area=><g key={area.id}><title>Cabin Area {area.id} · Centroid {area.centroid.toFixed(3)} {aircraft.armUnit==="IN"?"in":"m"}</title><text x={area.x} y={aircraft.centreY-20} textAnchor="middle" fontSize="2.5" fontWeight="600" fill="#555">Cabin Area {area.id}</text><line x1={area.x-4} x2={area.x+4} y1={aircraft.centreY-18} y2={aircraft.centreY-18} stroke={colours[areaIds.indexOf(area.id)%colours.length]} strokeWidth=".8"/></g>)}
    {rows.map(row=>{
      const colour=colours[areaIds.indexOf(row.areaId)%colours.length];
      const starts=seatMapGroupStarts(slots(row),seatWidth,aisle,gap);
      return <g key={row.rowNumber}><title>Cabin Area {row.areaId} · Row {row.rowNumber} · {row.groups.join("-")} · Balance Arm {row.centroid.toFixed(3)} {aircraft.armUnit==="IN"?"in":"m"}</title>
        {row.groups.flatMap((count,group)=>Array.from({length:count},(_,seat)=>{
          const seatY=aircraft.centreY+starts[group]+seat*(seatWidth+gap);
          if(row.blockedCentres&&seat===1)return <g key={`${group}-${seat}`}><title>Blocked centre seat — unavailable</title><rect x={row.x-depth/2} y={seatY} width={depth} height={seatWidth} rx=".35" fill="#F4F4F4" stroke="#777" strokeWidth=".22"/><path d={`M ${row.x-depth/2+.2} ${seatY+.2} L ${row.x+depth/2-.2} ${seatY+seatWidth-.2} M ${row.x+depth/2-.2} ${seatY+.2} L ${row.x-depth/2+.2} ${seatY+seatWidth-.2}`} stroke="#555" strokeWidth=".25"/></g>;
          return <g key={`${group}-${seat}`}><rect x={row.x-depth/2} y={seatY} width={depth} height={seatWidth} rx=".35" fill={colour} fillOpacity=".95" stroke="#444444" strokeWidth=".22"/><path d={`M ${row.x-depth/2+.4} ${seatY+.25} v ${Math.max(0,seatWidth-.5)}`} stroke={colour==="#444444"?"#EEEEEE":"#444444"} strokeWidth=".35"/></g>;
        }))}
        <text x={row.x} y={aircraft.centreY+18.5} textAnchor="middle" fontSize="2.2" fontWeight="700" fill="#444444">{row.rowNumber}</text>
      </g>;
    })}
  </svg></>;
}
