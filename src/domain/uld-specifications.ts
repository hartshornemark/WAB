export type UldInventoryRange={id:string|null;carrierCode:string;serialStart:string;serialEnd:string};
export type UldRow={isCustom:boolean;code:string;type:string;isDefault:boolean;tare:string;maximum:string;volume:string;remarks:string;inventory:UldInventoryRange[]};
export type MasterUld={code:string;type:string;tare:string;maximum:string;volume:string;mainDeckOnly:boolean};
export type UldSnapshot={canView:boolean;canEdit:boolean;revision:string;weightUnit:string;volumeUnit:string;utilisesUlds:boolean;aircraftType:string;aircraftSubtype:string;rows:UldRow[];master:MasterUld[]};
export class UldInvalid extends Error {}
export class UldDenied extends Error {}
export class UldConflict extends Error {}
export function normaliseUldSerial(value:string):string{return value.padStart(5,"0");}
export function uldDisplayValue(value:string,key:"tare"|"maximum"|"volume"):string{
 return value===""?"":String(Number(Number(value).toFixed(key==="volume"?2:0)));
}
export function uldEditRow(row:UldRow):UldRow{return {...row,tare:uldDisplayValue(row.tare,"tare"),maximum:uldDisplayValue(row.maximum,"maximum"),volume:uldDisplayValue(row.volume,"volume")};}
export function adoptUld(master:MasterUld,current:UldSnapshot,rows:UldRow[]):UldRow{
 const convert=(s:string,factor:number,places:number)=>s?String(Number((Number(s)*factor).toFixed(places))):"";
 const wf=current.weightUnit==="LB"?1/0.45359237:1,vf=current.volumeUnit==="ft3"?1/0.028316846592:1;
 return {isCustom:false,code:master.code,type:master.type,isDefault:!rows.some(r=>r.type===master.type),tare:convert(master.tare,wf,0),maximum:convert(master.maximum,wf,0),volume:convert(master.volume,vf,2),remarks:"",inventory:[]};
}
export function validateUlds(input:unknown,current:UldSnapshot):UldRow[]{
 if(!Array.isArray(input)||input.length>200)throw new UldInvalid("Keep no more than 200 ULD specifications.");
 const seen=new Set<string>();const defaults=new Map<string,number>();
 const rows=input.map((r:unknown)=>{
 if(!r||typeof r!=="object")throw new UldInvalid("Check the ULD entries.");const row=r as UldRow;
 if(typeof row.isCustom!=="boolean"||typeof row.code!=="string"||! /^[A-Z0-9]{3}$/.test(row.code)||typeof row.type!=="string"||! /^[A-Z0-9][A-Z0-9-]{0,5}$/.test(row.type))throw new UldInvalid("Enter a three-character ULD Code and a ULD Type of one to six letters, numbers or hyphens.");
 const master=current.master.find(m=>m.code===row.code);if(!row.isCustom&&!master)throw new UldInvalid("Choose a ULD from the master list, or add a Carrier ULD.");
 const type=row.isCustom?row.type:master!.type;
 if(seen.has(row.code))throw new UldInvalid("Each ULD code may appear only once.");seen.add(row.code);
 if(typeof row.isDefault!=="boolean"||typeof row.remarks!=="string"||row.remarks.length>2000)throw new UldInvalid("Check the default selection and keep remarks within 2,000 characters.");
 if(!Array.isArray(row.inventory)||row.inventory.length>100)throw new UldInvalid("Keep no more than 100 ULD inventory ranges for each ULD Code.");
 const inventoryKeys=new Set<string>();
 const inventory=row.inventory.map(range=>{
  if(!range||typeof range!=="object"||!(range.id===null||typeof range.id==="string")||typeof range.carrierCode!=="string"||!/^[A-Z0-9]{2}$/.test(range.carrierCode)||typeof range.serialStart!=="string"||!/^\d{1,5}$/.test(range.serialStart)||typeof range.serialEnd!=="string"||!/^\d{1,5}$/.test(range.serialEnd))throw new UldInvalid("Enter a Two-Character Carrier Code and Numeric Start/End Serial Numbers of No More than Five Digits.");
  if(Number(range.serialStart)>Number(range.serialEnd))throw new UldInvalid("End Serial must be the same as or greater than Start Serial.");
  const serialStart=normaliseUldSerial(range.serialStart),serialEnd=normaliseUldSerial(range.serialEnd);
  const key=`${range.carrierCode}:${serialStart}:${serialEnd}`;if(inventoryKeys.has(key))throw new UldInvalid("Each ULD inventory range must be unique.");inventoryKeys.add(key);
  return {...range,serialStart,serialEnd};
 });
 for(const key of ["tare","maximum","volume"] as const){const s=row[key];if(typeof s!=="string"||!/^\d+(\.\d{1,6})?$/.test(s)||!Number.isFinite(Number(s))||Number(s)>=1e12||Number(s)<0||(key!=="tare"&&Number(s)===0))throw new UldInvalid("Enter positive maximum weight and volume, and a non-negative tare weight. ");}
 if(!Number.isInteger(Number(row.tare))||!Number.isInteger(Number(row.maximum)))throw new UldInvalid("Tare Weight and Maximum Weight must be whole numbers.");
 if(!/^\d+(\.\d{1,2})?$/.test(String(Number(row.volume))))throw new UldInvalid("Maximum Volume may have no more than two decimal places.");
 if(Number(row.maximum)<Number(row.tare))throw new UldInvalid("Maximum Weight must be at least the Tare Weight.");
 defaults.set(type,(defaults.get(type)??0)+(row.isDefault?1:0));
 return {...row,type,inventory};
 });
 if([...defaults.values()].some(n=>n!==1))throw new UldInvalid("Choose exactly one Default for each adopted ULD Type.");
 return rows;
}

export function customUld(code:string,type:string,rows:UldRow[]):UldRow{
 code=code.trim().toUpperCase();type=type.trim().toUpperCase();
 if(!/^[A-Z0-9]{3}$/.test(code)||!/^[A-Z0-9][A-Z0-9-]{0,5}$/.test(type))throw new UldInvalid("Enter a three-character ULD Code and a ULD Type of one to six letters, numbers or hyphens.");
 if(rows.some(r=>r.code===code))throw new UldInvalid("This ULD Code has already been added.");
 return {isCustom:true,code,type,isDefault:!rows.some(r=>r.type===type),tare:"",maximum:"",volume:"",remarks:"",inventory:[]};
}
export function newInventoryRange():UldInventoryRange{return {id:null,carrierCode:"",serialStart:"",serialEnd:""};}
