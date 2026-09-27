import type { AircraftD2Snapshot, AircraftD2HoldRow } from "./aircraft-d2";
import type { AircraftD4Snapshot } from "./aircraft-d4";
import type { AircraftD3Position, AircraftD3Snapshot } from "./aircraft-d3";
import { aircraftD2Status } from "./aircraft-d2-status";
import { aircraftD4Status } from "./aircraft-d4-status";
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
export function applicableHolds(d2: AircraftD2Snapshot) {
  return d2.rows.filter(r => r.holdType === "BLK" ? d2.bulkApplicable === true : d2.uldApplicable === true);
}
function effectiveHoldArms(row: AircraftD2HoldRow, aircraft: AircraftLayoutCalibration) {
  const from = row.balanceFrom, to = row.balanceTo;
  if (from !== null || to !== null) {
    return typeof from === "number" && Number.isFinite(from) && typeof to === "number" && Number.isFinite(to) && from < to
      ? { from, to } : null;
  }
  return aircraft.holdArmDefaults?.[row.name] ?? null;
}
export function holdLayoutPrerequisite(d2: AircraftD2Snapshot): string | null {
  if (!d2.canView) return "You do not have permission to view the hold layout.";
  if (aircraftD2Status(d2) !== "configured") return "Complete all applicable D2 sections first.";
  if (!applicableHolds(d2).length) return "No applicable holds are available.";
  return null;
}
export function holdLayoutUnavailable(d2: AircraftD2Snapshot, aircraft: AircraftLayoutCalibration | undefined): string | null {
  if (!d2.canView) return "You do not have permission to view the hold layout.";
  if (!aircraft || aircraft.typeCode !== d2.typeCode || aircraft.subtype !== d2.subtype)
    return "A calibrated aircraft outline is not yet available for this aircraft.";
  if (aircraftD2Status(d2) !== "configured") return "Complete all applicable D2 sections first.";
  const rows = applicableHolds(d2);
  if (!rows.length) return "No applicable holds are available.";
  for (const row of rows) {
    const arms = effectiveHoldArms(row, aircraft);
    if (!arms)
      return `Hold ${row.name}: no global aircraft-type boundary is available. Supply valid Balance Arm From and To values in D2 to draw its length.`;
    if (holdLayoutX(arms.to, aircraft) < aircraft.cropLeft || holdLayoutX(arms.from, aircraft) > aircraft.cropRight)
      return `Hold ${row.name} falls outside the calibrated hold view. Check its D2 limits.`;
  }
  return null;
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
};
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
export function buildHoldLayout(d2: AircraftD2Snapshot, d4: AircraftD4Snapshot, d3: AircraftD3Snapshot | undefined, aircraft: AircraftLayoutCalibration): HoldLayout {
  const reason = holdLayoutUnavailable(d2, aircraft);
  if (reason) throw new Error(reason);
  const applicable = applicableHolds(d2);
  const usesGlobalHoldBoundaries = applicable.some(row => row.balanceFrom === null && row.balanceTo === null && !!aircraft.holdArmDefaults?.[row.name]);
  const holds = applicable.map(row => {
    const arms = effectiveHoldArms(row, aircraft)!;
    const armOffset = aircraft.holdArmOffsets?.[row.name] ?? 0;
    const x = holdLayoutX(arms.to + armOffset, aircraft);
    const width = holdLayoutX(arms.from + armOffset, aircraft) - x;
    const doorStartIds=aircraft.holdSubdivisionDoorStarts?.[row.name];
    const savedDoorBreaks=doorStartIds?.map(id=>d4.doors.find(door=>door.holdId===id)?.forwardArm)
      .filter((arm):arm is number=>typeof arm==="number"&&Number.isFinite(arm));
    const doorBreaks=savedDoorBreaks?.length===doorStartIds?.length?savedDoorBreaks:undefined;
    let subdivisions: LayoutSubdivision[] = [],uldPositions:LayoutUldPosition[]=[];
    if (row.holdType === "BLK") {
      const areas = row.compartments.flatMap(compartment => compartment.areas.map(area => {
        const centroid = validIndexPerWeightUnitFormula(d2.balanceFormula) && area.indexPerWeightUnit !== null
          ? balanceArmFromIndexPerWeightUnit(area.indexPerWeightUnit, d2.balanceFormula) : null;
        return { compartmentId: compartment.id, area, centroid };
      })).sort((a, b) => (b.centroid ?? 0) - (a.centroid ?? 0));
      const totalWeight = areas.reduce((sum, item) => sum + (item.area.maxWeight ?? 0), 0);
      let cursor = x;
      subdivisions = areas.map((item, index) => {
        const segmentWidth = index === areas.length - 1 ? x + width - cursor : totalWeight > 0 ? width * (item.area.maxWeight ?? 0) / totalWeight : width / areas.length;
        const result: LayoutSubdivision = { kind: "AREA", id: item.area.id, compartmentId: item.compartmentId, uldType: null,
          maxWeight: item.area.maxWeight, maxVolume: item.area.maxVolume, x: cursor, width: segmentWidth };
        cursor += segmentWidth;
        return result;
      });
      if (!subdivisions.length) subdivisions = fallbackSubdivisions(row, x, width, aircraft, armOffset, doorBreaks);
    } else if (d3?.canView && d3.typeCode === d2.typeCode && d3.subtype === d2.subtype) {
      const configurations = d3.configurations.filter(configuration => configuration.holdId === row.name && aircraftD3ConfigurationStatus(configuration) === "configured");
      const selected = configurations.find(configuration => configuration.description?.trim().toUpperCase() === "DEFAULT")
        ?? configurations.find(configuration => configuration.code.trim().toUpperCase() === "DEFAULT") ?? configurations[0];
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
    return { ...row, balanceFrom: arms.from, balanceTo: arms.to, x, width, subdivisions, uldPositions };
  });
  const sameAircraft = d2.typeCode === d4.typeCode && d2.subtype === d4.subtype;
  // D4 must be configured, and each applicable hold must have its own door.
  const doorsIncluded = d4.canView && sameAircraft && aircraftD4Status(d4) === "configured" && holds.every(h => d4.doors.some(d => d.holdId === h.name));
  const doors: LayoutDoor[] = [];
  if (doorsIncluded) for (const hold of holds) {
    const door = d4.doors.find(d => d.holdId === hold.name)!;
    const from = door.forwardArm!, to = door.aftArm!;
    // A door provides access to its associated hold, but the opening does not
    // have to lie inside that hold's D2 balance-arm limits. Keep the geometric
    // checks to the calibrated aircraft outline and let D4 own range validity.
    if (from >= to || holdLayoutX(to, aircraft) < aircraft.cropLeft || holdLayoutX(from, aircraft) > aircraft.cropRight)
      throw new Error(`Door ${hold.name}: its D4 Start/End values fall outside the calibrated aircraft view. Check D4 before viewing the layout.`);
    doors.push({ holdId: hold.name, deckCode: hold.deckCode, x: holdLayoutX(to, aircraft), width: holdLayoutX(from, aircraft) - holdLayoutX(to, aircraft), orientation: door.orientation! });
  }
  const uldArrangementSelectors:LayoutUldArrangementSelector[]=(aircraft.uldArrangementSelectors??[]).flatMap(selector=>{
    const hold=holds.find(item=>item.name===selector.holdId);
    if(!hold||!d3?.canView)return[];
    const configurations=d3.configurations.filter(configuration=>configuration.holdId===selector.holdId&&aircraftD3ConfigurationStatus(configuration)==="configured");
    const selected=configurations.find(configuration=>configuration.description?.trim().toUpperCase()==="DEFAULT")
      ??configurations.find(configuration=>configuration.code.trim().toUpperCase()==="DEFAULT")??configurations[0];
    const armOffset=aircraft.holdArmOffsets?.[selector.holdId]??0;
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
    return options.length?[{holdId:selector.holdId,uldType:selector.uldType,label:selector.label,options}]:[];
  });
  return { calibration: aircraft, typeCode: d2.typeCode, subtype: d2.subtype, holds, doors, doorsIncluded, usesGlobalHoldBoundaries,
    uldTypes:[...new Set(holds.flatMap(hold=>hold.uldPositions.map(position=>position.uldType)))].sort(),
    uldArrangementSelectors,
    decks: [...new Set(holds.map(h => h.deckCode))].map(code => ({ code, name: d2.deckTypes.find(d => d.code === code)?.name ?? code })) };
}
