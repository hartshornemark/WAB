import{indexForMacPercent,macPercentForIndex}from"@/domain/aircraft-balance-formula";
import type{AircraftC4Values}from"@/domain/aircraft-c4";

export type AircraftC7Point={weight:number;indexValue:number|null;macValue:number|null};
export type AircraftC7InputSource="INDEX"|"MAC";
export type AircraftC7PlottedPoint={weight:number;indexValue:number};
export type AircraftC7SectionKey="idealTrim"|"tippingLimits";
export type AircraftC7Section={enabled:boolean;points:AircraftC7Point[]};
export type AircraftC7Values={idealTrim:AircraftC7Section;tippingLimits:AircraftC7Section};
export type AircraftC7Snapshot={canView:boolean;canEdit:boolean;revision:string;typeCode:string;subtype:string;weightUnit:string;maximumRampWeight:number|null;values:AircraftC7Values};
export class AircraftC7Invalid extends Error{}
export class AircraftC7Denied extends Error{}
export class AircraftC7Conflict extends Error{}

const rounded=(value:number)=>Math.round(value*1_000_000)/1_000_000;
export function calculateAircraftC7Point(point:AircraftC7Point,source:AircraftC7InputSource,formula:AircraftC4Values|null):AircraftC7Point{
  const next={...point};
  if(!formula||!Number.isFinite(next.weight)||next.weight<=0)return next;
  if(source==="INDEX"&&next.indexValue!==null&&Number.isFinite(next.indexValue))next.macValue=rounded(macPercentForIndex(next.weight,next.indexValue,formula));
  if(source==="MAC"&&next.macValue!==null&&Number.isFinite(next.macValue))next.indexValue=rounded(indexForMacPercent(next.weight,next.macValue,formula));
  return next;
}

export function trimAircraftC7LineToMaximum(points:AircraftC7PlottedPoint[],maximumWeight:number):AircraftC7PlottedPoint[]{
  const ordered=[...points].sort((a,b)=>a.weight-b.weight),within=ordered.filter(point=>point.weight<=maximumWeight),above=ordered.find(point=>point.weight>maximumWeight),last=within.at(-1);
  if(!above||!last||last.weight===maximumWeight)return within;
  const fraction=(maximumWeight-last.weight)/(above.weight-last.weight);
  return[...within,{weight:maximumWeight,indexValue:last.indexValue+(above.indexValue-last.indexValue)*fraction}];
}

const finite=(value:unknown,label:string)=>{const n=typeof value==="number"?value:Number(value);if(value===""||value===null||value===undefined||!Number.isFinite(n)||Math.abs(n)>1_000_000_000)throw new AircraftC7Invalid(`Enter a valid ${label}.`);return n};
const optional=(value:unknown,label:string)=>value===""||value===null||value===undefined?null:finite(value,label);
export function validateAircraftC7Section(input:unknown,key:AircraftC7SectionKey,maximumRampWeight:number|null):AircraftC7Section{
  const value=input as Record<string,unknown>;
  if(typeof value?.enabled!=="boolean")throw new AircraftC7Invalid("Select whether this section applies.");
  if(!Array.isArray(value.points))throw new AircraftC7Invalid("The C7 points are incomplete.");
  const points=value.points.map((entry,index)=>{const row=entry as Record<string,unknown>,weight=finite(row.weight,`Weight at row ${index+1}`),indexValue=optional(row.indexValue,`Index at row ${index+1}`),macValue=optional(row.macValue,`% MAC/RC at row ${index+1}`);if(!Number.isInteger(weight)||weight<=0)throw new AircraftC7Invalid(`Weight at row ${index+1} must be a positive whole number.`);if(macValue!==null&&(macValue<0||macValue>100))throw new AircraftC7Invalid(`% MAC/RC at row ${index+1} must be between 0 and 100.`);if(indexValue===null&&macValue===null)throw new AircraftC7Invalid(`Enter an Index or % MAC/RC at row ${index+1}.`);if(maximumRampWeight&&weight>maximumRampWeight)throw new AircraftC7Invalid(`Weight at row ${index+1} cannot exceed MRW.`);return{weight,indexValue,macValue}}).sort((a,b)=>a.weight-b.weight);
  if(new Set(points.map(row=>row.weight)).size!==points.length)throw new AircraftC7Invalid("Each Weight may appear only once in a section.");
  return{enabled:value.enabled,points};
}
