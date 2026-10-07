import {d9SeatPlanProblem,type D9Configuration} from "./aircraft-d9";
import { type AircraftLayoutCalibration, holdLayoutX } from "./hold-layout";
import { buildD8Rows, physicalSeatGrouping, centreSeatsBlocked, normaliseSeatGrouping, seatGroupingCount, type AircraftD8Snapshot } from "./aircraft-d8";
import { aircraftD8Status } from "./aircraft-d8-status";
import { aircraftC4Status } from "./aircraft-c4-status";
import { balanceArmFromIndexPerWeightUnit } from "./index-per-weight-unit";
import type { AircraftC4Snapshot } from "./aircraft-c4";
import type { AircraftD5Snapshot } from "./aircraft-d5";

export type SeatMapRow = { areaId:string; rowNumber:number; centroid:number; x:number; groups:number[]; blockedCentres:boolean; seats:number };
export type SeatMapArea = {id:string; x:number; centroid:number};
export type SeatMap = { calibration:AircraftLayoutCalibration; longitudinalShift:number; typeCode:string; subtype:string; configurationCode?:string; configurationDescription?:string; decks:{code:string;rows:SeatMapRow[];areas:SeatMapArea[]}[] };

/** Normalise schematic glyphs to the internal scale of the aircraft SVG. */
export function seatMapDrawingScale(aircraft:Pick<AircraftLayoutCalibration,"imageFrame">):number {
 return aircraft.imageFrame.height/50;
}

/** The reviewed 767 master SVG is nose-left; D9 is consistently tail-left/nose-right. */
export function seatMapMirrorsAircraftProfile(aircraft:Pick<AircraftLayoutCalibration,"typeCode"|"subtype">):boolean {
 return aircraft.typeCode==="763"&&aircraft.subtype==="300";
}

/** Align the 767 D9 cabin with the reviewed over-wing exit reference at rows 25/26. */
export function seatMapLongitudinalShift(aircraft:Pick<AircraftLayoutCalibration,"typeCode"|"subtype"|"span"|"length">):number {
 return aircraft.typeCode==="763"&&aircraft.subtype==="300" ? -102*aircraft.span/aircraft.length : 0;
}

export function seatMapUnavailable(snapshot:AircraftD8Snapshot):string|null {
  if(!snapshot.canView)return "You do not have permission to view the seat map.";
  if(aircraftD8Status(snapshot)!=="configured")return "Complete the D8 seat rows before viewing the seat map.";
  for(const row of buildD8Rows(snapshot.cabinAreas,snapshot.rows,snapshot.excludedRows)) {
    const area=snapshot.cabinAreas.find(a=>a.id===row.areaId)!;
    try {
      const grouping=normaliseSeatGrouping(row.seatGroupingOverride??area.seatGrouping);
      if(!grouping)return `Cabin Area ${area.id}, Row ${row.rowNumber}: save a default seat grouping or a row override first.`;
      if(seatGroupingCount(grouping)!==row.maximumSeats)return `Row ${row.rowNumber}: seat grouping does not match Maximum Seats.`;
    } catch {return `Row ${row.rowNumber}: check its saved seat grouping.`;}
  }
  return null;
}

export function buildSeatMap(d8:AircraftD8Snapshot,c4:AircraftC4Snapshot,d5:AircraftD5Snapshot,configuration:D9Configuration|undefined,calibration:AircraftLayoutCalibration,savedLongitudinalShift?:number):SeatMap {
  if(!calibration || calibration.typeCode!==d8.typeCode || calibration.subtype!==d8.subtype)throw new Error("A calibrated aircraft outline is not yet available for this aircraft.");
  if(calibration.armUnit && calibration.armUnit!==c4.lengthUnit)throw new Error("Aircraft drawing and C4 length units do not match.");
  const reason=seatMapUnavailable(d8);if(reason)throw new Error(reason);
  if(!c4.canView||aircraftC4Status(c4)!=="configured")throw new Error("Configure C4 before viewing the seat map.");
  if(!d5.canView||[c4,d5].some(s=>s.typeCode!==d8.typeCode||s.subtype!==d8.subtype))throw new Error("Unable to match the saved aircraft configuration.");
  // Use this carrier's nose arm, with the same global SVG scale as the hold view.
  // Cargo-only drawing offsets must never move passenger rows.
  const aircraft={...calibration,noseArm:calibration.seatMapNoseArm??c4.values.datum,stationOriginX:undefined};
  const longitudinalShift=savedLongitudinalShift??seatMapLongitudinalShift(aircraft);
  const blockedRows=new Set(configuration?.rows.flatMap(r=>r.blockedRows??[])??[]);
  if(configuration){
    const physical=d8.rows.map(row=>({...row,grouping:row.seatGroupingOverride??d8.cabinAreas.find(a=>a.id===row.areaId)?.seatGrouping??null}));
    for(const area of d8.cabinAreas){const allocation=configuration.rows.find(r=>r.areaId===area.id);if(!allocation)throw new Error(`Configuration ${configuration.code}: complete Cabin Area ${area.id}.`);const problem=d9SeatPlanProblem(allocation,physical);if(problem)throw new Error(`Configuration ${configuration.code}: ${problem}`);}
  }
  const decks=new Map<string,SeatMapRow[]>();
  for(const row of buildD8Rows(d8.cabinAreas,d8.rows,d8.excludedRows)) {
    const area=d8.cabinAreas.find(a=>a.id===row.areaId)!;
    const deck=d5.cabinAreas.find(a=>a.id===row.areaId)?.deck;
    if(!deck)throw new Error(`Cabin Area ${area.id}: select its deck on D5.`);
    const centroid=balanceArmFromIndexPerWeightUnit(row.index!,{referenceArm:c4.values.referenceArm,constantC:c4.values.constantC});
    if(centroid<=aircraft.noseArm||centroid>=aircraft.noseArm+aircraft.length)throw new Error(`Row ${row.rowNumber}: its calculated position is outside the aircraft. Check C4 and D8.`);
    const rows=decks.get(deck)??[];
    rows.push({areaId:area.id,rowNumber:row.rowNumber,centroid,x:holdLayoutX(centroid,aircraft)+longitudinalShift,groups:physicalSeatGrouping(normaliseSeatGrouping(row.seatGroupingOverride??area.seatGrouping)!).split("-").map(Number),blockedCentres:configuration?blockedRows.has(row.rowNumber):centreSeatsBlocked(row.seatGroupingOverride??area.seatGrouping??""),seats:row.maximumSeats!-(configuration&&blockedRows.has(row.rowNumber)?physicalSeatGrouping(row.seatGroupingOverride??area.seatGrouping??"").split("-").length:0)});
    decks.set(deck,rows);
  }
  for(const rows of decks.values()) {
    rows.sort((a,b)=>a.centroid-b.centroid);
    for(let i=1;i<rows.length;i++)if(Math.abs(rows[i].x-rows[i-1].x)<.1)throw new Error(`Rows ${rows[i-1].rowNumber} and ${rows[i].rowNumber} have the same plotted position. Check their D8 Index Per Weight Unit values.`);
  }
  return {calibration:aircraft,longitudinalShift,typeCode:d8.typeCode,subtype:d8.subtype,configurationCode:configuration?.code,configurationDescription:configuration?.description,decks:[...decks].map(([code,rows])=>({code,rows,areas:[...new Set(rows.map(row=>row.areaId))].map(id=>{
    const area=d5.cabinAreas.find(area=>area.id===id)!;
    const areaRows=rows.filter(row=>row.areaId===id);
    const centroid=area.index!=null&&Number.isFinite(area.index)
      ?balanceArmFromIndexPerWeightUnit(area.index,{referenceArm:c4.values.referenceArm,constantC:c4.values.constantC})
      :area.centroid!=null&&Number.isFinite(area.centroid)?area.centroid
      :areaRows.reduce((sum,row)=>sum+row.centroid,0)/areaRows.length;
    return {id,centroid,x:holdLayoutX(centroid,aircraft)+longitudinalShift};
  })}))};
}

/** Reserve the widest peer group so aisles and outer seat blocks stay aligned. */
export function seatMapGroupSlots(groups:number[], peers:number[][]):number[]{
 const compatible=peers.filter(peer=>peer.length===groups.length);
 return groups.map((count,index)=>{
  const widest=Math.max(count,...compatible.map(peer=>peer[index]??0));
  return widest||Math.max(0,...groups);
 });
}
export function seatMapGroupStarts(slots:number[],seatWidth:number,aisle=1.8,gap=.35):number[]{
 const widths=slots.map(n=>n*seatWidth+Math.max(0,n-1)*gap);
 let cursor=-(widths.reduce((sum,n)=>sum+n,0)+(slots.length-1)*aisle)/2;
 return widths.map(w=>{const start=cursor;cursor+=w+aisle;return start;});
}
/** Centre a reduced seat group inside the space reserved by wider peer rows. */
export function seatMapGroupContentStarts(groups:number[],slots:number[],seatWidth:number,aisle=1.8,gap=.35):number[]{
 const starts=seatMapGroupStarts(slots,seatWidth,aisle,gap);
 return starts.map((start,index)=>start+Math.max(0,(slots[index]??0)-(groups[index]??0))*(seatWidth+gap)/2);
}

/** A single close pair must not flatten every seat in the cabin. */
export function seatMapSeatDepth(rows:Pick<SeatMapRow,"x">[],drawingScale=1):number {
 const positions=rows.map(r=>r.x).sort((a,b)=>a-b);
 const gaps=positions.slice(1).map((x,i)=>x-positions[i]).filter(n=>n>0).sort((a,b)=>a-b);
 const typical=gaps.length?gaps[Math.floor(gaps.length/2)]:Infinity;
 return Math.max(1.2*drawingScale,Math.min(2.7*drawingScale,typical*.65));
}
export function seatMapOverlaps(rows:SeatMapRow[],depth=seatMapSeatDepth(rows)):[number,number][] {
 const sorted=[...rows].sort((a,b)=>a.x-b.x);
 return sorted.slice(1).flatMap((row,i)=>row.x-sorted[i].x<depth?[[sorted[i].rowNumber,row.rowNumber] as [number,number]]:[]);
}
