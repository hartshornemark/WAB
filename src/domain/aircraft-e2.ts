import type {GalleyLocation} from "./aircraft-d6";

export type E2StartWeightPrinciple="BASIC_WEIGHT"|"DRY_OPERATING_WEIGHT"|null;
export type E2Deviation={isBase:boolean;weightAdjustment:number|null;indexAdjustment:number|null};
export type E2CrewRow=E2Deviation&{crewCode:string;flightDeckLocationId:string;flightDeckSeats:number|null;cabinCrewLocationId:string;cabinCrewSeats:number|null;flightDeckBaggageLocation:string|null;cabinCrewBaggageLocation:string|null};
export type E2PantryAdjustmentMethod="ONE_LINE"|"BY_GALLEY";
export type E2PantryRow=E2Deviation&{pantryCode:string;adjustmentMethod:E2PantryAdjustmentMethod;galleyLocations:string;totalWeight:number|null;balanceArm:number|null;index:number|null};
export type E2Location={id:string;description:string};
export type E2Hold={id:string;description:string};
export type AircraftE2Snapshot={canView:boolean;canEdit:boolean;revision:string;typeCode:string;subtype:string;startWeightPrinciple:E2StartWeightPrinciple;crewRows:E2CrewRow[];pantryRows:E2PantryRow[];flightDeckLocations:E2Location[];cabinCrewLocations:E2Location[];holds:E2Hold[];galleyLocations?:GalleyLocation[]};
export class AircraftE2Invalid extends Error{} export class AircraftE2Denied extends Error{} export class AircraftE2Conflict extends Error{}

const code=(v:unknown,label:string)=>{const s=String(v??"").trim().toUpperCase();if(!/^[A-Z0-9]$/.test(s))throw new AircraftE2Invalid(`${label} must contain one letter or number.`);return s};
const whole=(v:unknown,label:string,max=999)=>{const n=typeof v==="number"?v:Number(v);if(v===null||v===undefined||v===""||typeof v==="boolean"||!Number.isInteger(n)||n<0||n>max)throw new AircraftE2Invalid(`${label} must be a whole number of zero or more.`);return n};
const finite=(v:unknown,label:string)=>{const n=typeof v==="number"?v:Number(v);if(v===null||v===undefined||v===""||typeof v==="boolean"||!Number.isFinite(n)||Math.abs(n)>1e9)throw new AircraftE2Invalid(`Enter a valid ${label}.`);return n};
const deviation=(r:Partial<E2Deviation>,i:number,principle:E2StartWeightPrinciple,label:string):E2Deviation=>{
  if(principle!=="DRY_OPERATING_WEIGHT")return{isBase:false,weightAdjustment:null,indexAdjustment:null};
  const isBase=r.isBase===true;
  const weightAdjustment=finite(r.weightAdjustment,`${label} DOW Weight Adjustment at row ${i+1}`);
  const indexAdjustment=finite(r.indexAdjustment,`${label} DOI Adjustment at row ${i+1}`);
  if(!Number.isInteger(weightAdjustment))throw new AircraftE2Invalid(`${label} DOW Weight Adjustment at row ${i+1} must be a whole number.`);
  if(isBase&&(weightAdjustment!==0||indexAdjustment!==0))throw new AircraftE2Invalid(`The base ${label.toLowerCase()} code must have zero DOW and DOI adjustments.`);
  return{isBase,weightAdjustment,indexAdjustment};
};
const requireOneBase=<T extends E2Deviation>(rows:T[],principle:E2StartWeightPrinciple,label:string,codeOf:(row:T)=>string)=>{
  if(principle!=="DRY_OPERATING_WEIGHT")return;
  const bases=new Set(rows.filter(r=>r.isBase).map(codeOf));
  if(bases.size!==1)throw new AircraftE2Invalid(`Select exactly one base ${label.toLowerCase()} code. Its DOW and DOI adjustments are zero.`);
  const byCode=new Map<string,string>();
  for(const row of rows){const key=codeOf(row),value=`${row.isBase}|${row.weightAdjustment}|${row.indexAdjustment}`;if(byCode.has(key)&&byCode.get(key)!==value)throw new AircraftE2Invalid(`${label} Code ${key} must use the same base selection and DOW/DOI adjustments on every location row.`);byCode.set(key,value)}
};

export function validateE2Crew(v:unknown,flight:E2Location[],cabin:E2Location[],holds:E2Hold[],principle:E2StartWeightPrinciple=null){
  if(!Array.isArray(v))throw new AircraftE2Invalid("Crew Code rows are required.");
  const f=new Set(flight.map(x=>x.id)),c=new Set(cabin.map(x=>x.id)),h=new Set(holds.map(x=>x.id)),seen=new Set<string>();
  const rows=v.map((x,i)=>{
    const r=x as Partial<E2CrewRow>,crewCode=code(r.crewCode,`Crew Code at row ${i+1}`),flightDeckLocationId=String(r.flightDeckLocationId??"").trim().toUpperCase(),cabinCrewSeats=whole(r.cabinCrewSeats,`Cabin Crew Seats at row ${i+1}`),cabinCrewLocationId=cabinCrewSeats===0?"":String(r.cabinCrewLocationId??"").trim().toUpperCase(),flightDeckBaggageLocation=String(r.flightDeckBaggageLocation??"").trim().toUpperCase()||null,cabinCrewBaggageLocation=cabinCrewSeats===0?null:String(r.cabinCrewBaggageLocation??"").trim().toUpperCase()||null;
    if(!f.has(flightDeckLocationId)||(cabinCrewSeats>0&&!c.has(cabinCrewLocationId)))throw new AircraftE2Invalid(`Select valid crew locations at row ${i+1}.`);
    if((flightDeckBaggageLocation&&!h.has(flightDeckBaggageLocation))||(cabinCrewBaggageLocation&&!h.has(cabinCrewBaggageLocation)))throw new AircraftE2Invalid(`Select valid D2 holds for baggage locations at row ${i+1}.`);
    const key=[crewCode,flightDeckLocationId,cabinCrewLocationId].join("|");if(seen.has(key))throw new AircraftE2Invalid(`Crew Code location combination at row ${i+1} is duplicated.`);seen.add(key);
    return{crewCode,flightDeckLocationId,flightDeckSeats:whole(r.flightDeckSeats,`Flight Deck Seats at row ${i+1}`),cabinCrewLocationId,cabinCrewSeats,flightDeckBaggageLocation,cabinCrewBaggageLocation,...deviation(r,i,principle,"Crew")};
  });
  requireOneBase(rows,principle,"Crew",r=>r.crewCode);return rows;
}

export function validateE2Pantry(v:unknown,principle:E2StartWeightPrinciple=null){
  if(!Array.isArray(v))throw new AircraftE2Invalid("Pantry Code rows are required.");
  const seen=new Set<string>();
  const rows=v.map((x,i)=>{
    const r=x as Partial<E2PantryRow>,pantryCode=code(r.pantryCode,`Pantry Code at row ${i+1}`),adjustmentMethod:E2PantryAdjustmentMethod=principle==="DRY_OPERATING_WEIGHT"&&r.adjustmentMethod==="ONE_LINE"?"ONE_LINE":"BY_GALLEY",galleyLocations=String(r.galleyLocations??"").trim();
    if(r.isBase&&adjustmentMethod!=="BY_GALLEY")throw new AircraftE2Invalid("The base pantry code must be defined by galley; ALL GALLEYS is available for alternative codes.");
    if(!galleyLocations||galleyLocations.length>64)throw new AircraftE2Invalid(`Enter Galley Locations at row ${i+1}.`);
    if(seen.has(pantryCode))throw new AircraftE2Invalid(`Pantry Code ${pantryCode} is duplicated.`);seen.add(pantryCode);
    return{pantryCode,adjustmentMethod,galleyLocations,totalWeight:whole(r.totalWeight,`Total Weight at row ${i+1}`,2147483647),balanceArm:finite(r.balanceArm,`Balance Arm at row ${i+1}`),index:finite(r.index,`Index at row ${i+1}`),...deviation(r,i,principle,"Pantry")};
  });
  requireOneBase(rows,principle,"Pantry",r=>r.pantryCode);return rows;
}
