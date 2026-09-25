import {cabinRowNumbers} from "./cabin-row-sequence";
import{balanceArmFromIndexPerWeightUnit,validIndexPerWeightUnitFormula,type IndexPerWeightUnitFormula}from"@/domain/index-per-weight-unit";export type D8CabinArea={id:string;rowFrom:number;rowTo:number;rowSequence?:number[]|null;seatGrouping?:string|null};
export type SeatRow={areaId:string;rowNumber:number;maximumSeats:number|null;maximumWeight:number|null;centroid:number|null;index:number|null;seatGroupingOverride?:string|null};
export type AircraftD8Snapshot={canView:boolean;canEdit:boolean;revision:string;typeCode:string;subtype:string;excludedRows:number[];cabinAreas:D8CabinArea[];rows:SeatRow[];balanceFormula?:IndexPerWeightUnitFormula|null};
export class AircraftD8Invalid extends Error{} export class AircraftD8Denied extends Error{} export class AircraftD8Conflict extends Error{}
const finite=(v:unknown,label:string,positive=false,integer=false)=>{const n=typeof v==="number"?v:Number(v);if(v===null||v===""||typeof v==="boolean"||!Number.isFinite(n)||(positive&&n<=0)||(integer&&!Number.isInteger(n)))throw new AircraftD8Invalid(`Enter a valid ${label}.`);return n};
export function buildD8Rows(areas:D8CabinArea[],saved:SeatRow[],excludedRows:number[]=[]){const excluded=new Set(excludedRows),byRow=new Map(saved.filter(r=>!excluded.has(r.rowNumber)).map(r=>[r.rowNumber,r]));return areas.flatMap(a=>cabinRowNumbers(a,excludedRows).map(rowNumber=>(byRow.get(rowNumber)?.areaId===a.id?byRow.get(rowNumber):undefined)??{areaId:a.id,rowNumber,maximumSeats:null,maximumWeight:null,centroid:null,index:null}))}
export function validateD8Rows(input:unknown,areas:D8CabinArea[],formula?:IndexPerWeightUnitFormula|null,excludedRows:number[]=[]){if(!Array.isArray(input))throw new AircraftD8Invalid("Check the seat rows.");if(!validIndexPerWeightUnitFormula(formula))throw new AircraftD8Invalid("Configure C4 before calculating Balance Arm Centroid.");const excluded=new Set(excludedRows),entered=input.filter(v=>{const r=v as Record<string,unknown>;return r.maximumSeats!==null&&r.maximumSeats!==""||r.maximumWeight!==null&&r.maximumWeight!==""||r.index!==null&&r.index!==""});if(!entered.length)throw new AircraftD8Invalid("Complete at least one seat row.");const seen=new Set<number>();return entered.map((v,i)=>{const r=v as Partial<SeatRow>,area=areas.find(a=>a.id===String(r.areaId??"").trim());if(!area)throw new AircraftD8Invalid(`Select a valid Cabin Area at row ${i+1}.`);const rowNumber=finite(r.rowNumber,`Row Number at row ${i+1}`,true,true);if(!cabinRowNumbers(area).includes(rowNumber))throw new AircraftD8Invalid(`Row ${rowNumber} is outside Cabin Area ${area.id}.`);if(excluded.has(rowNumber))throw new AircraftD8Invalid(`Row ${rowNumber} is excluded on D5.`);if(seen.has(rowNumber))throw new AircraftD8Invalid(`Row ${rowNumber} is duplicated.`);seen.add(rowNumber);let maximumWeight:null|number=null;if((r.maximumWeight as unknown)!==null&&(r.maximumWeight as unknown)!=="")maximumWeight=finite(r.maximumWeight,`Maximum Weight (Kg) at row ${i+1}`,true);const index=finite(r.index,`Index per Weight Unit at row ${i+1}`);
const maximumSeats=finite(r.maximumSeats,`Maximum Seats at row ${i+1}`,true,true);
const seatGroupingOverride=normaliseSeatGrouping(r.seatGroupingOverride,`Row ${rowNumber}`);
const grouping=seatGroupingOverride??normaliseSeatGrouping(area.seatGrouping,`Cabin Area ${area.id}`);
if(grouping && seatGroupingCount(grouping)!==maximumSeats)throw new AircraftD8Invalid(`Row ${rowNumber}: seat grouping ${grouping} contains ${seatGroupingCount(grouping)} seats; Maximum Seats is ${maximumSeats}. Change the grouping or add a row override.`);
return{areaId:area.id,rowNumber,maximumSeats,seatGroupingOverride,maximumWeight,centroid:balanceArmFromIndexPerWeightUnit(index,formula),index}})}

/** Groups run left to right facing the nose; each hyphen represents an aisle. */
export function normaliseSeatGrouping(value: unknown, label = "Seat grouping"): string | null {
  if(value == null || value === "") return null;
  if(typeof value !== "string") throw new AircraftD8Invalid(`${label}: enter a grouping such as 3-3 or 2-4-2.`);
  const grouping=value.trim().replace(/[–—]/g,"-").replace(/\s*-\s*/g,"-");
  if(!grouping) return null;
  if(!/^(?:[0-9](-[0-9]){0,3}|3(-3){0,3}:B)$/.test(grouping) || !/[1-9]/.test(grouping)) throw new AircraftD8Invalid(`${label}: use one to four groups of 0–9 seats (at least one seat overall), separated by a hyphen (for example 3-3 or 0-2).`);
  return grouping;
}
export const physicalSeatGrouping=(grouping:string)=>grouping.replace(/:B$/, "");
export const centreSeatsBlocked=(grouping:string)=>grouping.endsWith(":B");
export const seatGroupingCount=(grouping:string)=>physicalSeatGrouping(grouping).split("-").reduce((sum,n)=>sum+Number(n)-(centreSeatsBlocked(grouping)?1:0),0);
export function validateD8AreaGroupings(input:unknown, areas:D8CabinArea[]):Record<string,string|null>{
  if(!input || typeof input!=="object" || Array.isArray(input)) throw new AircraftD8Invalid("Check the Cabin Area seat groupings.");
  return Object.fromEntries(Object.entries(input).map(([id,value])=>{
    if(!areas.some(area=>area.id===id))throw new AircraftD8Invalid(`Cabin Area ${id} is no longer available. Reload D8.`);
    return [id,normaliseSeatGrouping(value,`Cabin Area ${id}`)];
  }));
}
