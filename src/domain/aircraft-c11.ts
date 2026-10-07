export type AircraftC11Method="LINEAR"|"MATRIX";
export type AircraftC11MatrixRow={tow:number;trimValues:(number|null)[]};
export type AircraftC11Values={method:AircraftC11Method;macFwdLimit:number;macAftLimit:number;stabMaxValue:number;stabMinValue:number;variationFwd:number;variationAft:number;rateOfChange:number;macColumns:number[];rows:AircraftC11MatrixRow[]};
export type AircraftC11Snapshot={canView:boolean;canEdit:boolean;exists:boolean;revision:string;typeCode:string;subtype:string;values:AircraftC11Values};
export class AircraftC11Invalid extends Error{} export class AircraftC11Denied extends Error{} export class AircraftC11Conflict extends Error{}
const finite=(v:unknown,n:string)=>{const x=typeof v==="number"?v:Number(v);if(v===""||v===null||typeof v==="boolean"||!Number.isFinite(x)||Math.abs(x)>1e9)throw new AircraftC11Invalid(`Enter a valid ${n}.`);return x};
const strictlyAscending=(values:number[])=>values.every((value,index)=>index===0||value>values[index-1]);
export function validateAircraftC11(input:unknown){
 const v=input as Record<string,unknown>,method=String(v?.method??"LINEAR").toUpperCase() as AircraftC11Method;
 if(method==="LINEAR"){
  const r={method,macFwdLimit:finite(v?.macFwdLimit,"Forward MAC Limit"),macAftLimit:finite(v?.macAftLimit,"Aft MAC Limit"),stabMaxValue:finite(v?.stabMaxValue,"Maximum Stabiliser Value"),stabMinValue:finite(v?.stabMinValue,"Minimum Stabiliser Value"),variationFwd:finite(v?.variationFwd,"Forward Variation Point"),variationAft:finite(v?.variationAft,"Aft Variation Point")};
  if(!(r.macFwdLimit<=r.variationFwd&&r.variationFwd<r.variationAft&&r.variationAft<=r.macAftLimit))throw new AircraftC11Invalid("The variation range must sit inside the MAC range and its Aft point must be greater than its Forward point.");
  return r;
 }
 if(method!=="MATRIX")throw new AircraftC11Invalid("Select a valid C11.1 calculation method.");
 if(!Array.isArray(v.macColumns)||v.macColumns.length<2||v.macColumns.length>50)throw new AircraftC11Invalid("Add between 2 and 50 %MAC columns.");
 const macColumns=v.macColumns.map((value,index)=>finite(value,`%MAC column ${index+1}`));
 if(!strictlyAscending(macColumns))throw new AircraftC11Invalid("Enter the %MAC columns in ascending order without duplicates.");
 if(!Array.isArray(v.rows)||v.rows.length<2||v.rows.length>200)throw new AircraftC11Invalid("Add between 2 and 200 Actual TOW rows.");
 const rows=v.rows.map((source,rowIndex)=>{const row=source as Record<string,unknown>,tow=finite(row?.tow,`Actual TOW at row ${rowIndex+1}`);if(tow<=0||!Number.isSafeInteger(tow))throw new AircraftC11Invalid(`Actual TOW at row ${rowIndex+1} must be a positive whole number.`);if(!Array.isArray(row?.trimValues)||row.trimValues.length!==macColumns.length)throw new AircraftC11Invalid(`Row ${rowIndex+1} must contain one trim cell for every %MAC column.`);const trimValues=row.trimValues.map((value,columnIndex)=>value===""||value===null||value===undefined?null:finite(value,`trim value at row ${rowIndex+1}, column ${columnIndex+1}`));if(trimValues.filter(value=>value!==null).length<2)throw new AircraftC11Invalid(`Enter at least two stabiliser values on Actual TOW row ${rowIndex+1}.`);return{tow,trimValues}});
 if(!strictlyAscending(rows.map(row=>row.tow)))throw new AircraftC11Invalid("Enter the Actual TOW rows in ascending order without duplicates.");
 for(let column=0;column<macColumns.length;column++)if(!rows.some(row=>row.trimValues[column]!==null))throw new AircraftC11Invalid(`Enter at least one stabiliser value in the ${macColumns[column]}% MAC column.`);
 return{method,macColumns,rows};
}
/** Zero crossing of the plotted linear trim schedule; use endpoints to avoid rounded-rate drift. */
export function stabiliserZeroTrim(v:AircraftC11Values):{from:number;to:number}|null {
 if(v.method!=="LINEAR")return null;
 const delta=v.stabMinValue-v.stabMaxValue;
 if(delta===0)return v.stabMaxValue===0?{from:v.macFwdLimit,to:v.macAftLimit}:null;
 if(v.stabMaxValue===0)return{from:v.macFwdLimit,to:v.variationFwd};
 if(v.stabMinValue===0)return{from:v.variationAft,to:v.macAftLimit};
 const fraction=-v.stabMaxValue/delta;
 if(!Number.isFinite(fraction)||fraction<0||fraction>1)return null;
 const crossing=v.variationFwd+fraction*(v.variationAft-v.variationFwd);
 return{from:crossing,to:crossing};
}
