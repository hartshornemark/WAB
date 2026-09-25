/** Row numbers identify seats; this list records physical forward-to-aft order. */
export function cabinRowNumbers(area:{rowSequence?:number[]|null;rowFrom?:number|null;rowTo?:number|null;startRow?:number|null;endRow?:number|null},excluded:number[]=[]):number[]{
 const from=area.rowFrom??area.startRow,to=area.rowTo??area.endRow;
 const rows=area.rowSequence??(from!=null&&to!=null&&Number.isInteger(from)&&Number.isInteger(to)&&from>0&&to>=from&&to<=99?Array.from({length:to-from+1},(_,i)=>from+i):[]);
 return rows.filter(n=>!excluded.includes(n));
}
export function parseCabinRowSequence(value:unknown):number[]|null{
 if(value==null)return null;
 const raw=typeof value==="string"?value.split(",").map(s=>s.trim()):value;
 if(!Array.isArray(raw)||!raw.length||raw.some(n=>typeof n==="boolean"||n===""||!/^\d+$/.test(String(n))||Number(n)<1||Number(n)>99))throw new Error("Enter row numbers from 1 to 99, separated by commas, in forward-to-aft order.");
 const rows=raw.map(Number);
 if(new Set(rows).size!==rows.length)throw new Error("A row number appears more than once in the sequence.");
 return rows;
}
