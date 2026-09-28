export type AircraftC8SectionKey="standard"|"nonStandard"|"taxiFuel";
export type StandardFuelRow={specificGravity:number;fuelVolume:number|null;fuelWeight:number;hArm:number|null;indexValue:number};
export type TankFuelPoint={volume:number;balanceArm:number;importedWeight:number|null;importedIndex:number|null};
export type NonStandardFuelTank={tankName:string;tankShortCode:string;maximumVolume:number|null;sourceSpecificGravity:number|null;curveSpecificGravities?:number[];indexPerUnitWeight:number|null;weights:number[];points:TankFuelPoint[]};
export type FuelScheduleQuantityBasis="VOLUME"|"WEIGHT";
export type FuelLoadingScheduleStep={amount:number;tankCodes:string[]};
export type FuelLoadingSchedule={name:string;specificGravity:number;quantityBasis:FuelScheduleQuantityBasis;steps:FuelLoadingScheduleStep[]};
export type NonStandardFuelSection={byTankEnabled:boolean;byScheduleEnabled:boolean;tanks:NonStandardFuelTank[];schedules:FuelLoadingSchedule[]};
export type TaxiFuelRow={isDefault:boolean;airportIata:string|null;taxiFuel:number};
export type AircraftC8Values={standard:{enabled:boolean;rows:StandardFuelRow[]};nonStandard:NonStandardFuelSection;taxiFuel:{rows:TaxiFuelRow[]}};
export type AircraftC8Snapshot={canView:boolean;canEdit:boolean;revision:string;typeCode:string;subtype:string;weightUnit:string;lengthUnit:string;liquidVolumeUnit:string;values:AircraftC8Values};
export class AircraftC8Invalid extends Error{}
export class AircraftC8Denied extends Error{}
export class AircraftC8Conflict extends Error{}

const finite=(value:unknown,label:string)=>{const n=typeof value==="number"?value:Number(value);if(value===""||value===null||value===undefined||!Number.isFinite(n)||Math.abs(n)>1_000_000_000)throw new AircraftC8Invalid(`Enter a valid ${label}.`);return n};
const positive=(value:unknown,label:string)=>{const n=finite(value,label);if(n<=0)throw new AircraftC8Invalid(`${label} must be greater than zero.`);return n};
const wholePositive=(value:unknown,label:string)=>{const n=positive(value,label);if(!Number.isSafeInteger(n))throw new AircraftC8Invalid(`${label} must be a whole number.`);return n};
const wholeNonNegative=(value:unknown,label:string)=>{const n=finite(value,label);if(n<0||!Number.isSafeInteger(n))throw new AircraftC8Invalid(`${label} must be a whole number of zero or greater.`);return n};
const optional=(value:unknown,label:string)=>value===""||value===null||value===undefined?null:finite(value,label);
const optionalWholePositive=(value:unknown,label:string)=>value===""||value===null||value===undefined?null:wholePositive(value,label);
const optionalWholeNonNegative=(value:unknown,label:string)=>value===""||value===null||value===undefined?null:wholeNonNegative(value,label);
const text=(value:unknown,label:string,max:number)=>{const result=String(value??"").trim();if(!result||result.length>max)throw new AircraftC8Invalid(`Enter a ${label} of no more than ${max} characters.`);return result};

function validateNonStandard(value:Record<string,unknown>):NonStandardFuelSection{
 const byTankEnabled=value.byTankEnabled===true,byScheduleEnabled=value.byScheduleEnabled===true;
 if(typeof value.byTankEnabled!=="boolean"||typeof value.byScheduleEnabled!=="boolean"||!Array.isArray(value.tanks)||!Array.isArray(value.schedules))throw new AircraftC8Invalid("Select the applicable Non-Standard Fuel Loading method and complete its data.");
 const tanks=value.tanks.map((entry,tankIndex)=>{const r=entry as Record<string,unknown>,tankName=text(r.tankName,`Tank Name at tank ${tankIndex+1}`,80),tankShortCode=String(r.tankShortCode??"").trim().toUpperCase();if(!/^[A-Z0-9]{1,6}$/.test(tankShortCode))throw new AircraftC8Invalid(`Enter a Tank Short Code of one to six letters or numbers at tank ${tankIndex+1}.`);const maximumVolume=r.maximumVolume===""||r.maximumVolume===null||r.maximumVolume===undefined?null:wholePositive(r.maximumVolume,`Maximum Volume for ${tankShortCode}`),sourceSpecificGravity=r.sourceSpecificGravity===""||r.sourceSpecificGravity===null||r.sourceSpecificGravity===undefined?null:positive(r.sourceSpecificGravity,`Source Specific Gravity for ${tankShortCode}`),curveSpecificGravities=Array.isArray(r.curveSpecificGravities)?[...new Set(r.curveSpecificGravities.map((gravity,index)=>positive(gravity,`Generated Specific Gravity ${index+1} for ${tankShortCode}`)))].sort((a,b)=>a-b):[],indexPerUnitWeight=r.indexPerUnitWeight===""||r.indexPerUnitWeight===null||r.indexPerUnitWeight===undefined?null:finite(r.indexPerUnitWeight,`Index per Weight Unit for ${tankShortCode}`);if(!Array.isArray(r.weights)||!Array.isArray(r.points))throw new AircraftC8Invalid(`Complete the fuel data for ${tankShortCode}.`);const weights=r.weights.map((weight,weightIndex)=>wholeNonNegative(weight,`Weight at ${tankShortCode} row ${weightIndex+1}`)).sort((a,b)=>a-b);if(new Set(weights).size!==weights.length)throw new AircraftC8Invalid(`Each Weight may appear only once in the ${tankShortCode} By Tank table.`);if(byTankEnabled&&(indexPerUnitWeight===null||weights.length<1))throw new AircraftC8Invalid(`${tankShortCode} requires an Index per Weight Unit and at least one Weight for the By Tank method.`);const points=r.points.map((point,pointIndex)=>{const p=point as Record<string,unknown>,volume=wholeNonNegative(p.volume,`Volume at ${tankShortCode} row ${pointIndex+1}`),balanceArm=finite(p.balanceArm,`Balance Arm at ${tankShortCode} row ${pointIndex+1}`),importedWeight=optionalWholeNonNegative(p.importedWeight,`Imported Weight at ${tankShortCode} row ${pointIndex+1}`),importedIndex=optional(p.importedIndex,`Imported Index at ${tankShortCode} row ${pointIndex+1}`);if(maximumVolume!==null&&volume>maximumVolume)throw new AircraftC8Invalid(`Volume at ${tankShortCode} row ${pointIndex+1} cannot exceed the tank maximum.`);return{volume,balanceArm,importedWeight,importedIndex}}).sort((a,b)=>a.volume-b.volume);if(new Set(points.map(point=>point.volume)).size!==points.length)throw new AircraftC8Invalid(`Each Volume may appear only once in the ${tankShortCode} table.`);return{tankName,tankShortCode,maximumVolume,sourceSpecificGravity,curveSpecificGravities,indexPerUnitWeight,weights,points}});
 if((byTankEnabled||byScheduleEnabled)&&tanks.length===0)throw new AircraftC8Invalid("Add at least one fuel tank.");
 if(new Set(tanks.map(tank=>tank.tankShortCode)).size!==tanks.length)throw new AircraftC8Invalid("Each Tank Short Code may appear only once.");
 const tankCodes=new Set(tanks.map(tank=>tank.tankShortCode));
 const schedules=value.schedules.map((entry,scheduleIndex)=>{const r=entry as Record<string,unknown>,name=text(r.name,`Distribution Name at schedule ${scheduleIndex+1}`,100),specificGravity=positive(r.specificGravity,`Specific Gravity for ${name}`),rawQuantityBasis=r.quantityBasis;if(rawQuantityBasis!=="VOLUME"&&rawQuantityBasis!=="WEIGHT")throw new AircraftC8Invalid(`Select Volume or Weight for ${name}.`);const quantityBasis:FuelScheduleQuantityBasis=rawQuantityBasis;if(!Array.isArray(r.steps))throw new AircraftC8Invalid(`Complete the loading steps for ${name}.`);const steps=(r.steps as Record<string,unknown>[]).map((step,stepIndex)=>{const amount=positive(step.amount,`${quantityBasis==="VOLUME"?"Volume":"Weight"} Amount at ${name} step ${stepIndex+1}`),codes=Array.isArray(step.tankCodes)?step.tankCodes.map(code=>String(code).trim().toUpperCase()):[];if(codes.length===0||codes.some(code=>!tankCodes.has(code)))throw new AircraftC8Invalid(`Select at least one saved Tank at ${name} step ${stepIndex+1}.`);return{amount,tankCodes:[...new Set(codes)]}});if(byScheduleEnabled&&steps.length===0)throw new AircraftC8Invalid(`${name} requires at least one loading step.`);return{name,specificGravity,quantityBasis,steps}});
 if(new Set(schedules.map(schedule=>`${schedule.name.toUpperCase()}|${schedule.specificGravity}`)).size!==schedules.length)throw new AircraftC8Invalid("Each Distribution Name and Specific Gravity combination may appear only once.");
 return{byTankEnabled,byScheduleEnabled,tanks,schedules};
}

export function validateAircraftC8Section(input:unknown,key:AircraftC8SectionKey){
 const value=input as Record<string,unknown>;
 if(key==="nonStandard")return validateNonStandard(value);
 if(!Array.isArray(value?.rows))throw new AircraftC8Invalid("The C8 section is incomplete.");
 if(key==="taxiFuel"){
  const rows=value.rows.map((entry,index)=>{const r=entry as Record<string,unknown>,isDefault=r.isDefault===true,airport=String(r.airportIata??"").trim().toUpperCase();if(!isDefault&&!/^[A-Z]{3}$/.test(airport))throw new AircraftC8Invalid(`Enter a three-letter Airport IATA Code at row ${index+1}.`);return{isDefault,airportIata:isDefault?null:airport,taxiFuel:wholePositive(r.taxiFuel,`Taxi Fuel at row ${index+1}`)}});
  if(rows.filter(row=>row.isDefault).length!==1)throw new AircraftC8Invalid("Select exactly one Default Taxi Fuel row.");
  const airports=rows.flatMap(row=>row.airportIata?[row.airportIata]:[]);if(new Set(airports).size!==airports.length)throw new AircraftC8Invalid("Each Airport IATA Code may appear only once.");
  return{rows};
 }
 if(typeof value?.enabled!=="boolean")throw new AircraftC8Invalid("The C8 section is incomplete.");
 const rows=value.rows.map((entry,index)=>{const r=entry as Record<string,unknown>;return{specificGravity:positive(r.specificGravity,`Specific Gravity at row ${index+1}`),fuelVolume:optionalWholePositive(r.fuelVolume,`Fuel Volume at row ${index+1}`),fuelWeight:wholeNonNegative(r.fuelWeight,`Fuel Weight at row ${index+1}`),hArm:optional(r.hArm,`H-Arm at row ${index+1}`),indexValue:finite(r.indexValue,`Index at row ${index+1}`)}}).sort((a,b)=>a.fuelWeight-b.fuelWeight);
 if(new Set(rows.map(r=>`${r.fuelWeight}|${r.specificGravity}`)).size!==rows.length)throw new AircraftC8Invalid("Each Fuel Weight and Specific Gravity combination may appear only once.");
 for(const sg of new Set(rows.map(row=>row.specificGravity)))if(!rows.some(row=>row.specificGravity===sg&&row.fuelWeight===0))rows.push({specificGravity:sg,fuelWeight:0,fuelVolume:null,hArm:null,indexValue:0});
 rows.sort((a,b)=>a.fuelWeight-b.fuelWeight);
 return{enabled:value.enabled,rows};
}
