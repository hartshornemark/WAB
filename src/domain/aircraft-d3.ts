import {balanceArmCentroidInput,type IndexPerWeightUnitFormula} from "@/domain/index-per-weight-unit";

export type AircraftD3Hold={id:string;compartments?:string[]};
export type AircraftD3RowType="POSITION"|"GROUP_LIMIT";
export type AircraftD3UldOption={code:string;type:string;baseCode:string|null;baseWidth:number|null;baseLength:number|null;adopted:boolean};
export type AircraftD3AtomicBay={id:string;compartmentId:string;lateralCentroid:number|null;lateralFrom:number|null;lateralTo:number|null;balanceCentroid:number|null;balanceFrom:number|null;balanceTo:number|null;colour:string|null};
export type AircraftD3Position={rowType:AircraftD3RowType;positionId:string;compartmentId:string|null;uldCode:string|null;uldType:string|null;uldBaseCode:string|null;groupId:string|null;occupiedBayIds:string[];maxWeight:number|null;volume:number|null;lateralCentroid:number|null;lateralFrom:number|null;lateralTo:number|null;balanceCentroid:number|null;balanceFrom:number|null;balanceTo:number|null;indexPerWeightUnit:number|null;colour:string|null};
export type AircraftD3Configuration={holdId:string;code:string;description:string|null;expectedPositionCount:number;atomicBays:AircraftD3AtomicBay[];rows:AircraftD3Position[]};
export type AircraftD3Snapshot={canView:boolean;canEdit:boolean;revision:string;typeCode:string;subtype:string;uldHolds:AircraftD3Hold[];uldTypes:string[];uldOptions?:AircraftD3UldOption[];configurations:AircraftD3Configuration[];balanceFormula?:IndexPerWeightUnitFormula|null};
export type AircraftD3ConfigurationValues=AircraftD3Configuration;
export class AircraftD3Invalid extends Error{} export class AircraftD3Denied extends Error{} export class AircraftD3Conflict extends Error{}

/** Returns every other loading position blocked by the selected arrangement's occupied footprint. */
export function blockedAircraftD3PositionIds(configuration:AircraftD3Configuration,positionId:string,uldCode?:string){
 const selected=configuration.rows.find(row=>row.rowType==="POSITION"&&row.positionId===positionId&&(uldCode===undefined||row.uldCode===uldCode||(!row.uldCode&&row.uldType===uldCode)));
 if(!selected)return[];
 const occupied=new Set(selected.occupiedBayIds);
 return[...new Set(configuration.rows.filter(row=>row!==selected&&row.rowType==="POSITION"&&row.occupiedBayIds.some(bay=>occupied.has(bay))).map(row=>row.positionId))].sort();
}

const blank=(v:unknown)=>v===null||v===undefined||v==="";
const number=(v:unknown,label:string,required=true,positive=false)=>{if(blank(v)){if(required)throw new AircraftD3Invalid(`${label} is required.`);return null}const n=typeof v==="number"?v:Number(v);if(!Number.isFinite(n)||Math.abs(n)>1e9||(positive&&n<=0))throw new AircraftD3Invalid(`Enter a valid ${label}.`);return n};
const range=(from:unknown,centroid:unknown,to:unknown,label:string,centroidRequired=false)=>{const allBlank=blank(from)&&blank(centroid)&&blank(to);if(allBlank&&!centroidRequired)return[null,null,null]as const;const c=number(centroid,`${label} Centroid`);if(blank(from)&&blank(to))return[null,c,null]as const;if(blank(from)||blank(to))throw new AircraftD3Invalid(`${label} From and To must both be completed or both left blank.`);const f=number(from,`${label} From`),t=number(to,`${label} To`);if(!((f as number)<=c!&&c!<=(t as number)))throw new AircraftD3Invalid(`${label} must be ordered From, Centroid, To.`);return[f,c,t]as const};
const id=(v:unknown)=>String(v??"").trim().toUpperCase(),validId=(v:string)=>/^[A-Z0-9]{1,6}$/.test(v);

export function validateAircraftD3Configuration(input:unknown,holds:AircraftD3Hold[],formula?:IndexPerWeightUnitFormula|null,availableUldOptions:AircraftD3UldOption[]=[]):AircraftD3ConfigurationValues{
 const v=input as Partial<AircraftD3Configuration>,holdId=id(v?.holdId),code=id(v?.code),description=String(v?.description??"").trim()||null,selectedHold=holds.find(h=>h.id===holdId);
 if(!selectedHold)throw new AircraftD3Invalid("Select a valid ULD Hold.");
 if(!/^[A-Z0-9][A-Z0-9_-]{0,19}$/.test(code))throw new AircraftD3Invalid("Configuration Code must use 1–20 letters, numbers, hyphens or underscores.");
 const expected=Number(v?.expectedPositionCount);
 if(!Number.isInteger(expected)||expected<1||expected>999)throw new AircraftD3Invalid("Expected Atomic Bays must be a whole number from 1 to 999.");
 if(!Array.isArray(v?.atomicBays)||!Array.isArray(v?.rows))throw new AircraftD3Invalid("Check the D3 atomic bays and loading arrangements.");
 const bayIds=new Set<string>();
 const atomicBays=v.atomicBays.map((raw,index)=>{
  const b=raw as Partial<AircraftD3AtomicBay>,bayId=id(b.id),compartmentId=id(b.compartmentId);
  if(!validId(bayId))throw new AircraftD3Invalid(`Atomic Bay ${index+1}: ID must contain 1–6 letters or numbers.`);
  if(bayIds.has(bayId))throw new AircraftD3Invalid(`Atomic Bay ${bayId} is duplicated.`);
  bayIds.add(bayId);
  if(!compartmentId||(selectedHold.compartments!==undefined&&!selectedHold.compartments.includes(compartmentId)))throw new AircraftD3Invalid(`Atomic Bay ${bayId}: select a Compartment configured for ULD Hold ${holdId} on D2.`);
  const[lf,lc,lt]=range(b.lateralFrom,b.lateralCentroid,b.lateralTo,`Atomic Bay ${bayId} Lateral Arm`),[bf,bc,bt]=range(b.balanceFrom,b.balanceCentroid,b.balanceTo,`Atomic Bay ${bayId} Balance Arm`,true),colour=String(b.colour??"").trim()||null;
  if(colour!==null&&!/^#[0-9A-Fa-f]{6}$/.test(colour))throw new AircraftD3Invalid(`Atomic Bay ${bayId}: Colour must be a valid HEX value.`);
  return{id:bayId,compartmentId,lateralCentroid:lc,lateralFrom:lf,lateralTo:lt,balanceCentroid:bc,balanceFrom:bf,balanceTo:bt,colour};
 });
 if(atomicBays.length!==expected)throw new AircraftD3Invalid(`Expected ${expected} Atomic Bays but ${atomicBays.length} have been entered.`);
 const allowedOptions=new Map(availableUldOptions.filter(option=>option.adopted).map(option=>[option.code,option])),keys=new Set<string>();
 const rows=v.rows.map((raw,index)=>{
  const r=raw as Partial<AircraftD3Position>,rowType:AircraftD3RowType=r.rowType==="GROUP_LIMIT"?"GROUP_LIMIT":"POSITION",positionId=id(r.positionId),compartmentId=id(r.compartmentId)||null,uldCode=id(r.uldCode)||null,option=uldCode?allowedOptions.get(uldCode):undefined,uldType=option?.type??null,uldBaseCode=option?.baseCode??null,groupId=id(r.groupId)||null;
  if(!validId(positionId))throw new AircraftD3Invalid(`Arrangement ${index+1}: Position ID must contain 1–6 letters or numbers.`);
  if(rowType==="POSITION"&&(!compartmentId||(selectedHold.compartments!==undefined&&!selectedHold.compartments.includes(compartmentId))))throw new AircraftD3Invalid(`Arrangement ${positionId}: select a Compartment configured for ULD Hold ${holdId} on D2.`);
  if(rowType==="POSITION"&&(!uldCode||!option))throw new AircraftD3Invalid(`Arrangement ${positionId}: select a ULD Code configured on B5.`);
  if(groupId!==null&&(groupId.length>20||!/^[A-Z0-9_-]+$/.test(groupId)))throw new AircraftD3Invalid(`Arrangement ${positionId}: enter a valid Group ID.`);
  const key=`${rowType}\0${positionId}\0${uldCode??""}`;
  if(keys.has(key))throw new AircraftD3Invalid(`Arrangement ${positionId} / ${uldCode??"Group Limit"} is duplicated.`);
  keys.add(key);
  const occupiedBayIds=rowType==="POSITION"?[...new Set((r.occupiedBayIds??[]).map(id).filter(Boolean))]:[];
  if(rowType==="POSITION"&&!occupiedBayIds.length)throw new AircraftD3Invalid(`Arrangement ${positionId}: select at least one Atomic Bay that it occupies.`);
  const unknown=occupiedBayIds.find(x=>!bayIds.has(x));
  if(unknown)throw new AircraftD3Invalid(`Arrangement ${positionId}: Atomic Bay ${unknown} does not exist in this configuration.`);
  const[lf,lc,lt]=range(r.lateralFrom,r.lateralCentroid,r.lateralTo,"Lateral Arm"),indexPerWeightUnit=number(r.indexPerWeightUnit,"Index per Weight Unit",false),[bf,bc,bt]=range(r.balanceFrom,balanceArmCentroidInput(r.balanceCentroid,indexPerWeightUnit,formula),r.balanceTo,"Balance Arm",true),colour=String(r.colour??"").trim()||null;
  if(colour!==null&&!/^#[0-9A-Fa-f]{6}$/.test(colour))throw new AircraftD3Invalid(`Arrangement ${positionId}: Colour must be a valid HEX value.`);
  return{rowType,positionId,compartmentId:rowType==="POSITION"?compartmentId:null,uldCode:rowType==="POSITION"?uldCode:null,uldType:rowType==="POSITION"?uldType:null,uldBaseCode:rowType==="POSITION"?uldBaseCode:null,groupId,occupiedBayIds,maxWeight:number(r.maxWeight,"Maximum Weight",true,true),volume:number(r.volume,"Volume",false,true),lateralCentroid:lc,lateralFrom:lf,lateralTo:lt,balanceCentroid:bc,balanceFrom:bf,balanceTo:bt,indexPerWeightUnit,colour};
 });
 if(!rows.some(r=>r.rowType==="POSITION"))throw new AircraftD3Invalid("Add at least one permitted loading arrangement.");
 return{holdId,code,description,expectedPositionCount:expected,atomicBays,rows};
}
