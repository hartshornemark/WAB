export type AircraftC8SectionKey="standard"|"nonStandard"|"taxiFuel";
export type StandardFuelRow={specificGravity:number;fuelVolume:number|null;fuelWeight:number;hArm:number|null;indexValue:number};
export type NonStandardFuelRow={tankName:string;tankShortCode:string;specificGravity:number;maximumVolume:number;indexPerUnitWeight:number;balanceArm:number|null};
export type TaxiFuelRow={isDefault:boolean;airportIata:string|null;taxiFuel:number};
export type AircraftC8Values={standard:{enabled:boolean;rows:StandardFuelRow[]};nonStandard:{enabled:boolean;rows:NonStandardFuelRow[]};taxiFuel:{rows:TaxiFuelRow[]}};
export type AircraftC8Snapshot={canView:boolean;canEdit:boolean;revision:string;typeCode:string;subtype:string;weightUnit:string;lengthUnit:string;liquidVolumeUnit:string;values:AircraftC8Values};
export class AircraftC8Invalid extends Error{}
export class AircraftC8Denied extends Error{}
export class AircraftC8Conflict extends Error{}

const finite=(value:unknown,label:string)=>{const n=typeof value==="number"?value:Number(value);if(value===""||value===null||value===undefined||!Number.isFinite(n)||Math.abs(n)>1_000_000_000)throw new AircraftC8Invalid(`Enter a valid ${label}.`);return n};
const positive=(value:unknown,label:string)=>{const n=finite(value,label);if(n<=0)throw new AircraftC8Invalid(`${label} must be greater than zero.`);return n};
const wholePositive=(value:unknown,label:string)=>{const n=positive(value,label);if(!Number.isSafeInteger(n))throw new AircraftC8Invalid(`${label} must be a whole number.`);return n};
const optional=(value:unknown,label:string)=>value===""||value===null||value===undefined?null:finite(value,label);
const optionalWholePositive=(value:unknown,label:string)=>value===""||value===null||value===undefined?null:wholePositive(value,label);
export function validateAircraftC8Section(input:unknown,key:AircraftC8SectionKey){
 const value=input as Record<string,unknown>;if(!Array.isArray(value?.rows))throw new AircraftC8Invalid("The C8 section is incomplete.");
 if(key==="taxiFuel"){
  const rows=value.rows.map((entry,index)=>{const r=entry as Record<string,unknown>,isDefault=r.isDefault===true,airport=String(r.airportIata??"").trim().toUpperCase();if(!isDefault&&!/^[A-Z]{3}$/.test(airport))throw new AircraftC8Invalid(`Enter a three-letter Airport IATA Code at row ${index+1}.`);return{isDefault,airportIata:isDefault?null:airport,taxiFuel:wholePositive(r.taxiFuel,`Taxi Fuel at row ${index+1}`)}});
  if(rows.filter(row=>row.isDefault).length!==1)throw new AircraftC8Invalid("Select exactly one Default Taxi Fuel row.");
  const airports=rows.flatMap(row=>row.airportIata?[row.airportIata]:[]);if(new Set(airports).size!==airports.length)throw new AircraftC8Invalid("Each Airport IATA Code may appear only once.");
  return{rows};
 }
 if(typeof value?.enabled!=="boolean")throw new AircraftC8Invalid("The C8 section is incomplete.");
 if(key==="standard"){
  const rows=value.rows.map((entry,index)=>{const r=entry as Record<string,unknown>;return{specificGravity:positive(r.specificGravity,`Specific Gravity at row ${index+1}`),fuelVolume:optionalWholePositive(r.fuelVolume,`Fuel Volume at row ${index+1}`),fuelWeight:wholePositive(r.fuelWeight,`Fuel Weight at row ${index+1}`),hArm:optional(r.hArm,`H-Arm at row ${index+1}`),indexValue:finite(r.indexValue,`Index at row ${index+1}`)}}).sort((a,b)=>a.fuelWeight-b.fuelWeight);
  if(new Set(rows.map(r=>`${r.fuelWeight}|${r.specificGravity}`)).size!==rows.length)throw new AircraftC8Invalid("Each Fuel Weight and Specific Gravity combination may appear only once.");
  return{enabled:value.enabled,rows};
 }
 const rows=value.rows.map((entry,index)=>{const r=entry as Record<string,unknown>,tankName=String(r.tankName??"").trim(),tankShortCode=String(r.tankShortCode??"").trim().toUpperCase();if(!tankName||tankName.length>80)throw new AircraftC8Invalid(`Enter a Tank Name of no more than 80 characters at row ${index+1}.`);if(!/^[A-Z0-9]{3}$/.test(tankShortCode))throw new AircraftC8Invalid(`Enter a three-character Tank Short Code using letters or numbers at row ${index+1}.`);return{tankName,tankShortCode,specificGravity:positive(r.specificGravity,`Specific Gravity at row ${index+1}`),maximumVolume:wholePositive(r.maximumVolume,`Maximum Volume at row ${index+1}`),indexPerUnitWeight:finite(r.indexPerUnitWeight,`Index per Unit Weight at row ${index+1}`),balanceArm:optional(r.balanceArm,`Balance Arm at row ${index+1}`)}});
 if(new Set(rows.map(r=>r.tankShortCode)).size!==rows.length)throw new AircraftC8Invalid("Each Tank Short Code may appear only once.");
 return{enabled:value.enabled,rows};
}
