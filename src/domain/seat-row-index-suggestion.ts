type IndexRow={areaId:string;rowNumber:number;index:number|string|null};
function enteredIndex(value:IndexRow['index']):number|null{
 if(value===null||typeof value==='string'&&(!value.trim()||! /^[-+]?\d*(?:\.\d+)?$/.test(value.trim())))return null;
 const n=Number(value);return Number.isFinite(n)?n:null;
}
/** Rows must be supplied in D5 physical order, with excluded row labels removed. */
export function seatRowIndexSuggestion(rows:IndexRow[],position:number):number|null{
 const current=rows[position],previous=rows[position-1],before=rows[position-2];
 if(!current||!previous||!before||current.areaId!==previous.areaId||current.areaId!==before.areaId)return null;
 // Never overwrite an entered value, including invalid text awaiting correction.
 if(current.index!==null&&String(current.index).trim()!=='')return null;
 const a=enteredIndex(before.index),b=enteredIndex(previous.index);
 if(a===null||b===null)return null;
 const result=Number((b+(b-a)).toFixed(5));
 return Number.isFinite(result)?(Object.is(result,-0)?0:result):null;
}
