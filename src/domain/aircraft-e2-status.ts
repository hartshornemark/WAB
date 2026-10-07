import type{DisplayConfigurationStatus}from"@/domain/configuration-status";
import type{AircraftE2Snapshot,E2CrewRow,E2PantryRow}from"@/domain/aircraft-e2";
const completeDeviation=(r:{isBase:boolean;weightAdjustment:number|null;indexAdjustment:number|null})=>Number.isInteger(r.weightAdjustment)&&Number.isFinite(r.indexAdjustment)&&(!r.isBase||(r.weightAdjustment===0&&r.indexAdjustment===0));
const oneBase=<T extends {isBase:boolean}>(rows:T[],code:(row:T)=>string)=>new Set(rows.filter(r=>r.isBase).map(code)).size===1;
const consistent=<T extends {isBase:boolean;weightAdjustment:number|null;indexAdjustment:number|null}>(rows:T[],code:(row:T)=>string)=>{const seen=new Map<string,string>();return rows.every(r=>{const k=code(r),v=`${r.isBase}|${r.weightAdjustment}|${r.indexAdjustment}`,previous=seen.get(k);seen.set(k,v);return previous===undefined||previous===v})};
const completeCrew=(r:E2CrewRow)=>!!r.crewCode&&!!r.flightDeckLocationId&&Number.isInteger(r.flightDeckSeats)&&r.flightDeckSeats!>=0&&(r.cabinCrewSeats===0||!!r.cabinCrewLocationId)&&Number.isInteger(r.cabinCrewSeats)&&r.cabinCrewSeats!>=0;
const completePantry=(r:E2PantryRow)=>!!r.pantryCode&&!!r.galleyLocations&&Number.isInteger(r.totalWeight)&&r.totalWeight!>=0&&Number.isFinite(r.balanceArm)&&Number.isFinite(r.index);
const status=<T>(rows:T[],complete:(r:T)=>boolean):DisplayConfigurationStatus=>rows.length&&rows.every(complete)?"configured":rows.length?"partial":"incomplete";
export const e2CrewStatus=(s:AircraftE2Snapshot)=>status(s.crewRows,r=>completeCrew(r)&&(s.startWeightPrinciple!=="DRY_OPERATING_WEIGHT"||(completeDeviation(r)&&oneBase(s.crewRows,x=>x.crewCode)&&consistent(s.crewRows,x=>x.crewCode))));
export const e2PantryStatus=(s:AircraftE2Snapshot)=>status(s.pantryRows,r=>completePantry(r)&&(s.startWeightPrinciple!=="DRY_OPERATING_WEIGHT"||(completeDeviation(r)&&oneBase(s.pantryRows,x=>x.pantryCode)&&consistent(s.pantryRows,x=>x.pantryCode))));
export function aircraftE2Status(s:AircraftE2Snapshot):DisplayConfigurationStatus{const a=e2CrewStatus(s),b=e2PantryStatus(s);return a==="configured"&&b==="configured"?"configured":a!=="incomplete"||b!=="incomplete"?"partial":"incomplete"}
