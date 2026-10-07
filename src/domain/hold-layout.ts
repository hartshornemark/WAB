import { aircraftD2HoldId, bulkHoldIdentity, type AircraftD2Snapshot, type AircraftD2HoldRow } from "./aircraft-d2";
import type { AircraftD4Snapshot } from "./aircraft-d4";
import type { AircraftD3Position, AircraftD3Snapshot } from "./aircraft-d3";
import { aircraftD2Status } from "./aircraft-d2-status";
import { aircraftD4Status, aircraftD4DoorComplete } from "./aircraft-d4-status";
import { aircraftD3ConfigurationStatus } from "./aircraft-d3-status";
import { balanceArmFromIndexPerWeightUnit, validIndexPerWeightUnitFormula } from "./index-per-weight-unit";

export type AircraftLayoutCalibration = {
  typeCode: string; subtype: string; length: number; noseArm: number;
  tailX: number; span: number; centreY: number; asset: string;
  imageFrame: Readonly<{ x: number; y: number; width: number; height: number }>;
  cropLeft: number; cropRight: number; holdY: number; holdHeight: number;
  leftDoorY: number; rightDoorY: number; labelCharWidth: number;
  armUnit?: "IN" | "M";
  stationOriginX?: number;
  seatMapNoseArm?: number;
  seatMapCaption?: string;
  reviewDoorArmOffset?: number;
  diagramCaption?: string;
  combinedHoldProfile?: { points: {arm:number;halfWidth:number}[]; joinArm:number };
  holdProfiles?: Readonly<Record<string, { points: {arm:number;halfWidth:number}[] }>>;
  holdArmOffsets?: Readonly<Record<string, number>>;
  holdArmDefaults?: Readonly<Record<string, Readonly<{ from: number; to: number }>>>;
  holdSubdivisionBreaks?: Readonly<Record<string, readonly number[]>>;
  holdSubdivisionDoorStarts?: Readonly<Record<string, readonly string[]>>;
  uldArrangementSelectors?: readonly {
    holdId: string;
    uldType: string;
    label: string;
    options: readonly {
      id: string;
      label: string;
      includedPositionIds: readonly string[];
      uldCode?: string;
      referencePositionId?: string;
      referenceUldCode?: string;
      excludedPositionIds?: readonly string[];
    }[];
  }[];
};

export function holdLayoutX(arm: number, aircraft: AircraftLayoutCalibration) {
  return (aircraft.stationOriginX ?? aircraft.tailX) - (arm - (aircraft.stationOriginX === undefined ? aircraft.noseArm : 0)) * aircraft.span / aircraft.length;
}
export function holdLayoutMirrorsAircraftProfile(aircraft:Pick<AircraftLayoutCalibration,"typeCode"|"subtype">) {
  return aircraft.typeCode==="763"&&aircraft.subtype==="300";
}
function holdLayoutArm(x:number,aircraft:AircraftLayoutCalibration){
  return (aircraft.stationOriginX===undefined?aircraft.noseArm:0)+((aircraft.stationOriginX??aircraft.tailX)-x)*aircraft.length/aircraft.span;
}
export function applicableHolds(d2: AircraftD2Snapshot) {
  return d2.rows.filter(r => r.holdType === "BLK" ? d2.bulkApplicable === true : d2.uldApplicable === true);
}
function selectedHoldConfiguration(row: AircraftD2HoldRow, d2: AircraftD2Snapshot, d3?: AircraftD3Snapshot) {
  if (!d3?.canView || d3.typeCode !== d2.typeCode || d3.subtype !== d2.subtype) return undefined;
  const configurations = d3.configurations.filter(c => c.holdId === aircraftD2HoldId(row) && aircraftD3ConfigurationStatus(c) === "configured");
  return configurations.find(c => c.description?.trim().toUpperCase() === "DEFAULT")
    ?? configurations.find(c => c.code.trim().toUpperCase() === "DEFAULT") ?? configurations[0];
}
function inferredBulkHoldArms(row: AircraftD2HoldRow, d2?: AircraftD2Snapshot) {
  if (row.holdType !== "BLK" || !validIndexPerWeightUnitFormula(d2?.balanceFormula)) return null;
  const centroids = row.compartments
    .flatMap(compartment => compartment.areas)
    .map(area => area.indexPerWeightUnit === null ? null : balanceArmFromIndexPerWeightUnit(area.indexPerWeightUnit, d2!.balanceFormula!))
    .filter((value): value is number => value !== null && Number.isFinite(value))
    .sort((left, right) => left - right);
  if (centroids.length < 2 || centroids.some((value, index) => index > 0 && value <= centroids[index - 1])) return null;
  const firstHalfSpacing = (centroids[1] - centroids[0]) / 2;
  const lastHalfSpacing = (centroids.at(-1)! - centroids.at(-2)!) / 2;
  return {
    from: centroids[0] - firstHalfSpacing,
    to: centroids.at(-1)! + lastHalfSpacing,
    source: "areas" as const,
  };
}
function holdCalibrationValue<T>(values: Readonly<Record<string, T>> | undefined, row: AircraftD2HoldRow): T | undefined {
  if (!values) return undefined;
  const family = bulkHoldIdentity(row.name).holdId;
  return values[aircraftD2HoldId(row)] ?? values[row.name] ?? values[family]
    ?? (row.name === "ALB" ? values["5"] : undefined);
}
function holdArmOffset(aircraft:AircraftLayoutCalibration,row:AircraftD2HoldRow){
  return holdCalibrationValue(aircraft.holdArmOffsets,row)??(row.name==="ALB"?aircraft.holdArmOffsets?.AFT:undefined)??0;
}
export function aircraftHoldProfile(aircraft: AircraftLayoutCalibration, row: AircraftD2HoldRow) {
  return holdCalibrationValue(aircraft.holdProfiles, row);
}
function profiledHoldArms(row: AircraftD2HoldRow, aircraft: AircraftLayoutCalibration) {
  const arms = aircraftHoldProfile(aircraft, row)?.points.map(point => point.arm).filter(Number.isFinite) ?? [];
  if (arms.length < 2) return null;
  const from = Math.min(...arms), to = Math.max(...arms);
  return from < to ? { from, to, source: "global" as const } : null;
}
function selectedUldFootprint(row: AircraftD2HoldRow, d2?: AircraftD2Snapshot, d3?: AircraftD3Snapshot) {
  if (row.holdType !== "ULD" || !d2) return null;
  const selected = selectedHoldConfiguration(row, d2, d3);
  const bays = selected?.atomicBays ?? [];
  if (!bays.length || bays.some(bay => bay.balanceFrom === null || bay.balanceTo === null
    || !Number.isFinite(bay.balanceFrom) || !Number.isFinite(bay.balanceTo) || bay.balanceFrom >= bay.balanceTo)) return null;
  return {
    from: Math.min(...bays.map(bay => bay.balanceFrom!)),
    to: Math.max(...bays.map(bay => bay.balanceTo!)),
  };
}
function effectiveHoldArms(row: AircraftD2HoldRow, aircraft: AircraftLayoutCalibration, d2?: AircraftD2Snapshot, d3?: AircraftD3Snapshot) {
  const from = row.balanceFrom, to = row.balanceTo;
  if (from !== null || to !== null) {
    if (!(typeof from === "number" && Number.isFinite(from) && typeof to === "number" && Number.isFinite(to) && from < to)) return null;
    const footprint = selectedUldFootprint(row, d2, d3);
    // D2 describes the hold outline while D3 contains its physical bays. A
    // stale or rounded D2 limit must never clip a configured bay from view.
    return footprint ? { from: Math.min(from, footprint.from), to: Math.max(to, footprint.to),
      source: footprint.from < from || footprint.to > to ? "expanded-positions" as const : undefined } : { from, to };
  }
  const defaults = holdCalibrationValue(aircraft.holdArmDefaults, row);
  if (defaults) return {...defaults, source: "global" as const};
  const profileArms = profiledHoldArms(row, aircraft);
  if (profileArms) return profileArms;
  const bulkAreaArms = inferredBulkHoldArms(row, d2);
  if (bulkAreaArms) return bulkAreaArms;
  // Saved D3 footprints describe the occupied range, not certified hold walls.
  const footprint = selectedUldFootprint(row, d2, d3);
  if (footprint) return {...footprint, source: "positions" as const};
  const selected = row.holdType === "ULD" && d2 ? selectedHoldConfiguration(row, d2, d3) : undefined;
  const positions = selected?.rows.filter(p => p.rowType === "POSITION") ?? [];
  if (!positions.length || positions.some(p => p.balanceFrom === null || p.balanceTo === null || !Number.isFinite(p.balanceFrom) || !Number.isFinite(p.balanceTo) || p.balanceFrom >= p.balanceTo)) return null;
  return {from: Math.min(...positions.map(p => p.balanceFrom!)), to: Math.max(...positions.map(p => p.balanceTo!)), source: "positions" as const};
}
export function holdLayoutPrerequisite(d2: AircraftD2Snapshot): string | null {
  if (!d2.canView) return "You do not have permission to view the hold layout.";
  if (aircraftD2Status(d2) !== "configured") return "Complete all applicable D2 sections first.";
  if (!applicableHolds(d2).length) return "No applicable holds are available.";
  return null;
}
export function holdLayoutUnavailable(d2: AircraftD2Snapshot, aircraft: AircraftLayoutCalibration | undefined, d3?: AircraftD3Snapshot): string | null {
  if (!d2.canView) return "You do not have permission to view the hold layout.";
  if (!aircraft || aircraft.typeCode !== d2.typeCode || aircraft.subtype !== d2.subtype)
    return "A calibrated aircraft outline is not yet available for this aircraft.";
  if (aircraftD2Status(d2) !== "configured") return "Complete all applicable D2 sections first.";
  const rows = applicableHolds(d2);
  if (!rows.length) return "No applicable holds are available.";
  let plotted = 0;
  for (const row of rows) {
    const arms = effectiveHoldArms(row, aircraft, d2, d3);
    if (!arms) {
      if (d3 && row.balanceFrom === null && row.balanceTo === null) continue;
      return `Hold ${row.name}: no global aircraft-type boundary is available. Supply valid Balance Arm From and To values in D2 to draw its length.`;
    }
    plotted++;
    if (holdLayoutX(arms.to, aircraft) < aircraft.cropLeft || holdLayoutX(arms.from, aircraft) > aircraft.cropRight)
      return `Hold ${row.name} falls outside the calibrated hold view. Check its D2 limits.`;
  }
  return plotted ? null : "No hold ranges are available. Supply D2 From/To limits or complete D3 position footprints.";
}
export type LayoutSubdivision = {
  kind: "HOLD" | "COMPARTMENT" | "AREA" | "BAY"; id: string; compartmentId: string;
  uldType: string | null; maxWeight: number | null; maxVolume: number | null;
  x: number; width: number;
};
export type LayoutUldPosition = {
  id: string; compartmentId: string; uldType: string; uldCodes: string[];
  x: number; width: number;
  sourceX?: number; sourceWidth?: number;
  codeRanges?: { uldCode: string; x: number; width: number }[];
};
export function separateUldPositionDisplayRanges(positions: LayoutUldPosition[], holdX: number, holdWidth: number) {
  const result=positions.map(position=>({...position})),holdEnd=holdX+holdWidth;
  for(const uldType of new Set(result.map(position=>position.uldType))) {
    const family=result.filter(position=>position.uldType===uldType);
    for(const lane of ["SIDE","FULL"] as const) {
      const lanePositions=family.filter(position=>/[LR]$/i.test(position.id.trim())?(lane==="SIDE"):(lane==="FULL"));
      const groups=new Map<string,LayoutUldPosition[]>();
      for(const position of lanePositions) {
        const key=lane==="SIDE"?position.id.trim().replace(/[LR]$/i,""):position.id.trim();
        groups.set(key,[...(groups.get(key)??[]),position]);
      }
      const ordered=[...groups.values()].map(group=>({group,centre:group.reduce((sum,position)=>sum+position.x+position.width/2,0)/group.length}))
        .sort((left,right)=>left.centre-right.centre);
      ordered.forEach((entry,index)=>{
        const rawStart=Math.min(...entry.group.map(position=>position.x));
        const rawEnd=Math.max(...entry.group.map(position=>position.x+position.width));
        const start=index===0?Math.max(holdX,rawStart):(ordered[index-1].centre+entry.centre)/2;
        const end=index===ordered.length-1?Math.min(holdEnd,rawEnd):(entry.centre+ordered[index+1].centre)/2;
        for(const position of entry.group){position.x=start;position.width=Math.max(0,end-start)}
      });
    }
  }
  return result;
}
export type LayoutHold = AircraftD2HoldRow & { x: number; width: number; subdivisions: LayoutSubdivision[]; uldPositions: LayoutUldPosition[] };
export type LayoutDoor = { holdId: string; deckCode: string; x: number; width: number; orientation: "L" | "R" | "C" };
export type LayoutUldArrangementOption = {
  id: string; label: string; includedPositionIds: string[]; excludedPositionIds: string[]; uldCode: string | null;
  referencePosition: LayoutUldPosition | null;
};
export type LayoutUldArrangementSelector = {
  holdId: string; uldType: string; label: string;
  options: LayoutUldArrangementOption[];
};
export type HoldLayout = {
  calibration: AircraftLayoutCalibration;
  typeCode: string; subtype: string; doorsIncluded: boolean; usesGlobalHoldBoundaries: boolean;
  holds: LayoutHold[]; doors: LayoutDoor[]; decks: { code: string; name: string }[]; uldTypes: string[];
  uldArrangementSelectors: LayoutUldArrangementSelector[];
  boundaryNotes?: string[];
};
function automaticUldArrangementSelectors(holds:LayoutHold[]):LayoutUldArrangementSelector[]{
  return holds.flatMap(hold=>[...new Set(hold.uldPositions.map(position=>position.uldType))].flatMap(uldType=>{
    const positions=hold.uldPositions.filter(position=>position.uldType===uldType);
    const groups=new Map<string,LayoutUldPosition[]>();
    for(const position of positions){
      const id=position.id.replace(/[LR]$/i,"");
      groups.set(id,[...(groups.get(id)??[]),position]);
    }
    const intervals=[...groups].map(([id,members])=>({id,members,
      from:Math.min(...members.map(item=>item.sourceX??item.x)),
      to:Math.max(...members.map(item=>(item.sourceX??item.x)+(item.sourceWidth??item.width))),
    })).sort((left,right)=>left.from-right.from||left.id.localeCompare(right.id));
    const conflicts=(left:typeof intervals[number],right:typeof intervals[number])=>left.from<right.to-1e-6&&right.from<left.to-1e-6;
    const conflicted=intervals.filter((item,index)=>intervals.some((other,otherIndex)=>index!==otherIndex&&conflicts(item,other)));
    if(!conflicted.length||conflicted.length>12)return[];
    const fixed=intervals.filter(item=>!conflicted.includes(item));
    const candidates=[] as (typeof intervals)[];
    for(let mask=1;mask<(1<<conflicted.length);mask++){
      const chosen=conflicted.filter((_,index)=>(mask&(1<<index))!==0);
      if(chosen.some((item,index)=>chosen.slice(index+1).some(other=>conflicts(item,other))))continue;
      if(conflicted.some(item=>!chosen.includes(item)&&chosen.every(other=>!conflicts(item,other))))continue;
      candidates.push(chosen);
    }
    if(candidates.length<2||candidates.length>16)return[];
    const options=candidates.map(chosen=>{
      const included=[...fixed,...chosen].flatMap(item=>item.members.map(member=>member.id));
      const ids=chosen.map(item=>item.id).sort((left,right)=>left.localeCompare(right,undefined,{numeric:true}));
      return{id:ids.join("-"),label:ids.join(" + "),includedPositionIds:included,
        excludedPositionIds:positions.map(item=>item.id).filter(id=>!included.includes(id)),uldCode:null,referencePosition:null};
    }).sort((left,right)=>left.label.localeCompare(right.label,undefined,{numeric:true}));
    return[{holdId:aircraftD2HoldId(hold),uldType,label:`HOLD ${hold.name} ARRANGEMENT`,options}];
  }));
}
function fallbackSubdivisions(row: AircraftD2HoldRow, x: number, width: number, aircraft: AircraftLayoutCalibration, armOffset: number, savedDoorBreaks?: readonly number[]): LayoutSubdivision[] {
  if (!row.compartments.length) return [{ kind: "HOLD", id: row.name, compartmentId: "", uldType: null,
    maxWeight: row.maxWeight, maxVolume: row.maxVolume, x, width }];
  // D2 records compartments from the aircraft nose aft. Diagrams are drawn
  // tail-left / nose-right, so visual placement must use the reverse order.
  const compartments=row.compartments.toReversed(),breaks=savedDoorBreaks??aircraft.holdSubdivisionBreaks?.[row.name];
  if(breaks?.length!==compartments.length-1)return compartments.map((compartment,index)=>({kind:"COMPARTMENT",id:compartment.id,compartmentId:compartment.id,
    uldType:null,maxWeight:null,maxVolume:null,x:x+width*index/compartments.length,width:width/compartments.length}));
  const edges=[x,...breaks.map(arm=>holdLayoutX(arm+armOffset,aircraft)).sort((a,b)=>a-b),x+width];
  return compartments.map((compartment,index)=>({kind:"COMPARTMENT",id:compartment.id,compartmentId:compartment.id,
    uldType:null,maxWeight:null,maxVolume:null,x:edges[index],width:edges[index+1]-edges[index]}));
}
export function buildHoldLayout(d2: AircraftD2Snapshot, d4: AircraftD4Snapshot, d3: AircraftD3Snapshot | undefined, aircraft: AircraftLayoutCalibration, sourceD2:AircraftD2Snapshot=d2): HoldLayout {
  const reason = holdLayoutUnavailable(d2, aircraft, d3);
  if (reason) throw new Error(reason);
  const applicable = applicableHolds(d2);
  const usesGlobalHoldBoundaries = applicable.some(row => row.balanceFrom === null && row.balanceTo === null
    && (!!holdCalibrationValue(aircraft.holdArmDefaults, row) || !!profiledHoldArms(row, aircraft)));
  const boundaryNotes: string[] = [];
  const holds = applicable.flatMap(row => {
    const arms = effectiveHoldArms(row, aircraft, d2, d3);
    const label = `${d2.deckTypes.find(d => d.code === row.deckCode)?.name ?? row.deckCode} — Hold ${row.name}`;
    if (!arms) {
      boundaryNotes.push(`${label}: not drawn; enter its From and To limits in D2.`);
      return [];
    }
    if ("source" in arms && arms.source === "positions") boundaryNotes.push(`${label}: outline shows the occupied D3 position range; D2 hold limits have not been supplied.`);
    if ("source" in arms && arms.source === "expanded-positions") boundaryNotes.push(`${label}: D2 limits were expanded to include every configured D3 physical bay.`);
    if ("source" in arms && arms.source === "areas") boundaryNotes.push(`${label}: outline is derived from its saved Area centroids; D2 hold limits have not been supplied.`);
    const armOffset = holdArmOffset(aircraft,row);
    let plottedFrom=arms.from,plottedTo=arms.to;
    let x = holdLayoutX(plottedTo + armOffset, aircraft);
    let width = holdLayoutX(plottedFrom + armOffset, aircraft) - x;
    const doorStartIds=aircraft.holdSubdivisionDoorStarts?.[row.name];
    const savedDoorBreaks=doorStartIds?.map(id=>d4.doors.find(door=>door.holdId===id)?.forwardArm)
      .filter((arm):arm is number=>typeof arm==="number"&&Number.isFinite(arm));
    const doorBreaks=savedDoorBreaks?.length===doorStartIds?.length?savedDoorBreaks:undefined;
    let subdivisions: LayoutSubdivision[] = [],uldPositions:LayoutUldPosition[]=[];
    if (row.holdType === "BLK") {
      const sourceRow=sourceD2.rows.find(item=>aircraftD2HoldId(item)===aircraftD2HoldId(row))??row;
      const areaKey=(compartmentId:string,areaId:string)=>`${compartmentId}\0${areaId}`;
      const selectedAreas=new Map(row.compartments.flatMap(compartment=>compartment.areas.map(area=>[areaKey(compartment.id,area.id),{compartmentId:compartment.id,area}] as const)));
      const areas = sourceRow.compartments.flatMap(compartment => compartment.areas.map(area => {
        const centroid = validIndexPerWeightUnitFormula(sourceD2.balanceFormula) && area.indexPerWeightUnit !== null
          ? balanceArmFromIndexPerWeightUnit(area.indexPerWeightUnit, sourceD2.balanceFormula) : null;
        return { key:areaKey(compartment.id,area.id),compartmentId: compartment.id, area, centroid };
      })).sort((a, b) => (b.centroid ?? 0) - (a.centroid ?? 0));
      const centroids=areas.map(item=>item.centroid);
      const useCentroids=centroids.length>0&&centroids.every((value):value is number=>value!==null&&Number.isFinite(value))
        &&centroids.every((value,index)=>index===0||(centroids[index-1] as number)>value)
        &&(centroids[0] as number)<arms.to&&(centroids.at(-1) as number)>arms.from;
      const armEdges=useCentroids?[arms.to,...(centroids as number[]).slice(0,-1).map((value,index)=>(value+(centroids[index+1] as number))/2),arms.from]:null;
      const totalWeight = areas.reduce((sum, item) => sum + (item.area.maxWeight ?? 0), 0);
      let cursor = x;
      subdivisions = areas.flatMap((item, index) => {
        const selected=selectedAreas.get(item.key);
        const segmentX=armEdges?holdLayoutX(armEdges[index]+armOffset,aircraft):cursor;
        const segmentWidth=armEdges?holdLayoutX(armEdges[index+1]+armOffset,aircraft)-segmentX:index === areas.length - 1 ? x + width - cursor : totalWeight > 0 ? width * (item.area.maxWeight ?? 0) / totalWeight : width / areas.length;
        cursor=segmentX+segmentWidth;
        return selected?[{ kind: "AREA" as const, id: selected.area.id, compartmentId: selected.compartmentId, uldType: null,
          maxWeight: selected.area.maxWeight, maxVolume: selected.area.maxVolume, x: segmentX, width: segmentWidth }]:[];
      });
      if(subdivisions.length&&selectedAreas.size<areas.length){
        const end=Math.max(...subdivisions.map(segment=>segment.x+segment.width));
        x=Math.min(...subdivisions.map(segment=>segment.x));width=end-x;
        plottedTo=Math.round((holdLayoutArm(x,aircraft)-armOffset)*1e6)/1e6;
        plottedFrom=Math.round((holdLayoutArm(end,aircraft)-armOffset)*1e6)/1e6;
      }
      if (!subdivisions.length) subdivisions = fallbackSubdivisions(row, x, width, aircraft, armOffset, doorBreaks);
    } else if (d3?.canView && d3.typeCode === d2.typeCode && d3.subtype === d2.subtype) {
      const selected = selectedHoldConfiguration(row, d2, d3);
      const positionsByTypeAndId=new Map<string,AircraftD3Position[]>();
      for(const position of selected?.rows.filter(position=>position.rowType==="POSITION"&&position.uldType)??[]){
        const positionKey=`${position.uldType}\0${position.positionId}`;
        positionsByTypeAndId.set(positionKey,[...(positionsByTypeAndId.get(positionKey)??[]),position]);
      }
      uldPositions=[...positionsByTypeAndId.values()].flatMap(positions=>{
        const fromValues=positions.map(position=>position.balanceFrom).filter((value):value is number=>value!==null&&Number.isFinite(value));
        const toValues=positions.map(position=>position.balanceTo).filter((value):value is number=>value!==null&&Number.isFinite(value));
        if(!fromValues.length||!toValues.length)return[];
        const from=Math.min(...fromValues),to=Math.max(...toValues),first=positions[0];
        const codeRanges=[...new Set(positions.map(position=>position.uldCode).filter((code):code is string=>!!code))].sort().flatMap(uldCode=>{
          const codeRows=positions.filter(position=>position.uldCode===uldCode);
          const codeFrom=codeRows.map(position=>position.balanceFrom).filter((value):value is number=>value!==null&&Number.isFinite(value));
          const codeTo=codeRows.map(position=>position.balanceTo).filter((value):value is number=>value!==null&&Number.isFinite(value));
          if(!codeFrom.length||!codeTo.length)return[];
          const rangeFrom=Math.min(...codeFrom),rangeTo=Math.max(...codeTo);
          return[{uldCode,x:holdLayoutX(rangeTo+armOffset,aircraft),width:holdLayoutX(rangeFrom+armOffset,aircraft)-holdLayoutX(rangeTo+armOffset,aircraft)}];
        });
        const sourceX=holdLayoutX(to+armOffset,aircraft),sourceWidth=holdLayoutX(from+armOffset,aircraft)-sourceX;
        return[{id:first.positionId,compartmentId:first.compartmentId??"",uldType:first.uldType!,uldCodes:codeRanges.map(range=>range.uldCode),codeRanges,x:sourceX,width:sourceWidth,sourceX,sourceWidth}];
      }).sort((left,right)=>left.x-right.x||left.id.localeCompare(right.id));
      uldPositions=separateUldPositionDisplayRanges(uldPositions,x,width);
      // D3 separates the aircraft's atomic physical bays from the alternative
      // ULD arrangements that may occupy several of them. The hold diagram is
      // physical, so it must draw the atomic bays once rather than drawing each
      // overlapping loading arrangement as another piece of aircraft structure.
      const bays = selected?.atomicBays
        .toSorted((a, b) => (b.balanceCentroid ?? 0) - (a.balanceCentroid ?? 0)) ?? [];
      const compartmentSections = fallbackSubdivisions(row, x, width, aircraft, armOffset, doorBreaks);
      const hasCalibratedCompartments = (doorBreaks??aircraft.holdSubdivisionBreaks?.[row.name])?.length === row.compartments.length - 1
        && compartmentSections.every(section => section.kind === "COMPARTMENT")
        && bays.every(position => compartmentSections.some(section => section.id === position.compartmentId));
      // A calibrated compartment boundary remains authoritative when D3 adds
      // physical ULD positions. Divide the bays inside their compartment rather
      // than redistributing every bay equally across the whole hold.
      const savedFootprint = (bay: typeof bays[number]): LayoutSubdivision | null =>
        bay.balanceFrom !== null && bay.balanceTo !== null
          ? { kind: "BAY", id: bay.id, compartmentId: bay.compartmentId, uldType: null, maxWeight: null, maxVolume: null,
              x: holdLayoutX(bay.balanceTo + armOffset, aircraft),
              width: holdLayoutX(bay.balanceFrom + armOffset, aircraft) - holdLayoutX(bay.balanceTo + armOffset, aircraft) }
          : null;
      const exactBays = bays.map(savedFootprint);
      subdivisions = exactBays.length > 0 && exactBays.every((bay): bay is LayoutSubdivision => bay !== null) ? exactBays : hasCalibratedCompartments ? compartmentSections.flatMap(section => {
        const compartmentBays = bays.filter(position => position.compartmentId === section.id);
        return compartmentBays.map((position, index) => ({ kind: "BAY" as const, id: position.id, compartmentId: position.compartmentId, uldType: null,
          maxWeight: null, maxVolume: null, x: section.x + section.width * index / compartmentBays.length, width: section.width / compartmentBays.length }));
      }) : bays.map((position, index) => ({ kind: "BAY", id: position.id, compartmentId: position.compartmentId, uldType: null,
        maxWeight: null, maxVolume: null, x: x + width * index / bays.length, width: width / bays.length }));
      if (!subdivisions.length) subdivisions = fallbackSubdivisions(row, x, width, aircraft, armOffset, doorBreaks);
    } else {
      subdivisions = fallbackSubdivisions(row, x, width, aircraft, armOffset, doorBreaks);
    }
    return [{ ...row, balanceFrom: plottedFrom, balanceTo: plottedTo, x, width, subdivisions, uldPositions }];
  });
  const sameAircraft = d2.typeCode === d4.typeCode && d2.subtype === d4.subtype;
  // D4 must be configured, and each hold marked as having a door must have its own definition.
  const doorHolds = applicable.filter(hold => hold.hasDoor !== false);
  const doorsIncluded = d4.canView && sameAircraft && aircraftD4Status(d4) === "configured" && doorHolds.every(h => d4.doors.some(d => d.holdId === aircraftD2HoldId(h)));
  const doors: LayoutDoor[] = [];
  if (doorsIncluded) for (const hold of doorHolds) {
    const holdId = aircraftD2HoldId(hold);
    const door = d4.doors.find(d => d.holdId === holdId)!;
    if (!aircraftD4DoorComplete(door)) continue;
    const doorArmOffset=aircraft.reviewDoorArmOffset??0;
    const from = door.forwardArm!+doorArmOffset, to = door.aftArm!+doorArmOffset;
    // A door provides access to its associated hold, but the opening does not
    // have to lie inside that hold's D2 balance-arm limits. Keep the geometric
    // checks to the calibrated aircraft outline and let D4 own range validity.
    if (from >= to || holdLayoutX(to, aircraft) < aircraft.cropLeft || holdLayoutX(from, aircraft) > aircraft.cropRight)
      throw new Error(`Door ${hold.name}: its D4 Start/End values fall outside the calibrated aircraft view. Check D4 before viewing the layout.`);
    doors.push({ holdId, deckCode: hold.deckCode, x: holdLayoutX(to, aircraft), width: holdLayoutX(from, aircraft) - holdLayoutX(to, aircraft), orientation: door.orientation! });
  }
  const configuredArrangementSelectors:LayoutUldArrangementSelector[]=(aircraft.uldArrangementSelectors??[]).flatMap(selector=>{
    const hold=holds.find(item=>item.name===selector.holdId);
    if(!hold||!d3?.canView)return[];
    const holdId=aircraftD2HoldId(hold);
    const configurations=d3.configurations.filter(configuration=>configuration.holdId===holdId&&aircraftD3ConfigurationStatus(configuration)==="configured");
    const selected=configurations.find(configuration=>configuration.description?.trim().toUpperCase()==="DEFAULT")
      ??configurations.find(configuration=>configuration.code.trim().toUpperCase()==="DEFAULT")??configurations[0];
    const armOffset=holdArmOffset(aircraft,hold);
    const options=selector.options.flatMap(option=>{
      const row=option.referencePositionId&&option.referenceUldCode?selected?.rows.find(position=>position.rowType==="POSITION"&&position.positionId===option.referencePositionId
        &&position.uldCode===option.referenceUldCode&&position.balanceFrom!==null&&position.balanceTo!==null):undefined;
      if((option.referencePositionId||option.referenceUldCode)&&(!row||row.balanceFrom===null||row.balanceTo===null))return[];
      const referencePosition=row&&row.balanceFrom!==null&&row.balanceTo!==null?{
        id:row.positionId,compartmentId:row.compartmentId??"",uldType:row.uldType??selector.uldType,uldCodes:[row.uldCode!],
        x:holdLayoutX(row.balanceTo+armOffset,aircraft),width:holdLayoutX(row.balanceFrom+armOffset,aircraft)-holdLayoutX(row.balanceTo+armOffset,aircraft),
      }:null;
      return[{id:option.id,label:option.label,includedPositionIds:[...option.includedPositionIds],excludedPositionIds:[...(option.excludedPositionIds??[])],uldCode:option.uldCode??null,referencePosition}];
    });
    return options.length?[{holdId,uldType:selector.uldType,label:selector.label,options}]:[];
  });
  const automaticArrangementSelectors=automaticUldArrangementSelectors(holds).filter(automatic=>!configuredArrangementSelectors.some(configured=>configured.holdId===automatic.holdId&&configured.uldType===automatic.uldType));
  const uldArrangementSelectors=[...configuredArrangementSelectors,...automaticArrangementSelectors];
  return { calibration: aircraft, typeCode: d2.typeCode, subtype: d2.subtype, holds, doors, doorsIncluded, usesGlobalHoldBoundaries,
    uldTypes:[...new Set(holds.flatMap(hold=>hold.uldPositions.map(position=>position.uldType)))].sort(),
    uldArrangementSelectors, boundaryNotes,
    decks: [...new Set(applicable.map(h => h.deckCode))].sort((a,b) => (["MDECK","MAIN"].includes(a)?0:a==="LOWER"?1:2)-(["MDECK","MAIN"].includes(b)?0:b==="LOWER"?1:2)).map(code => ({ code, name: d2.deckTypes.find(d => d.code === code)?.name ?? code })) };
}
