import type{NonStandardFuelTank,TankFuelPoint}from"./aircraft-c8";

export type TankCurveImportRow={line:number;tankShortCode:string;tankName:string|null;maximumVolume:number|null;sourceSpecificGravity:number|null;point:TankFuelPoint};
export type TankCurveImportResult={rows:TankCurveImportRow[];errors:string[]};

export const tankCurveCsvTemplate="Tank Code,Tank Name,Maximum Volume,Volume,Balance Arm,Weight,Index,Source SG\n";

const headerKey=(value:string)=>value.trim().toLowerCase().replace(/[^a-z0-9]/g,"");
const aliases:Record<string,string[]>={tankShortCode:["tankcode","tankshortcode","tank"],tankName:["tankname","name"],maximumVolume:["maximumvolume","maxvolume","tankmaximumvolume"],volume:["volume","fuelvolume"],balanceArm:["balancearm","arm","harm"],importedWeight:["weight","fuelweight"],importedIndex:["index","indexvalue"],sourceSpecificGravity:["sourcesg","specificgravity","sg","fueldensity"]};

function csvRows(text:string){const rows:string[][]=[];let row:string[]=[],field="",quoted=false;for(let index=0;index<text.length;index++){const char=text[index];if(quoted){if(char==='"'&&text[index+1]==='"'){field+='"';index++}else if(char==='"')quoted=false;else field+=char}else if(char==='"')quoted=true;else if(char===','){row.push(field);field=""}else if(char==='\n'){row.push(field.replace(/\r$/,"").trim());if(row.some(value=>value!==""))rows.push(row);row=[];field=""}else field+=char}row.push(field.replace(/\r$/,"").trim());if(row.some(value=>value!==""))rows.push(row);return rows}
const number=(value:string|undefined)=>{if(value===undefined||value.trim()==="")return null;const result=Number(value);return Number.isFinite(result)?result:Number.NaN};

export function parseTankCurveCsv(text:string):TankCurveImportResult{
 const raw=csvRows(text.replace(/^\uFEFF/,"")),errors:string[]=[],rows:TankCurveImportRow[]=[];
 if(raw.length===0)return{rows,errors:["The CSV file is empty."]};
 const headers=raw[0].map(headerKey),columns=Object.fromEntries(Object.entries(aliases).map(([key,names])=>[key,headers.findIndex(header=>names.includes(header))])) as Record<keyof typeof aliases,number>;
 for(const required of ["tankShortCode","volume","balanceArm"] as const)if(columns[required]<0)errors.push(`Missing required column: ${required==="tankShortCode"?"Tank Code":required==="balanceArm"?"Balance Arm":"Volume"}.`);
 if(errors.length)return{rows,errors};
 raw.slice(1).forEach((values,rowIndex)=>{const line=rowIndex+2,at=(key:keyof typeof aliases)=>columns[key]<0?undefined:values[columns[key]],tankShortCode=String(at("tankShortCode")??"").trim().toUpperCase(),tankName=String(at("tankName")??"").trim()||null,maximumVolume=number(at("maximumVolume")),volume=number(at("volume")),balanceArm=number(at("balanceArm")),importedWeight=number(at("importedWeight")),importedIndex=number(at("importedIndex")),sourceSpecificGravity=number(at("sourceSpecificGravity"));
  if(!/^[A-Z0-9]{1,6}$/.test(tankShortCode))errors.push(`Line ${line}: Tank Code must contain one to six letters or numbers.`);
  if(volume===null||!Number.isSafeInteger(volume)||volume<0)errors.push(`Line ${line}: Volume must be a whole number of zero or greater.`);
  if(balanceArm===null||!Number.isFinite(balanceArm))errors.push(`Line ${line}: Balance Arm is required.`);
  if(maximumVolume!==null&&(!Number.isSafeInteger(maximumVolume)||maximumVolume<=0))errors.push(`Line ${line}: Maximum Volume must be a positive whole number.`);
  if(importedWeight!==null&&(!Number.isSafeInteger(importedWeight)||importedWeight<0))errors.push(`Line ${line}: Weight must be a whole number of zero or greater.`);
  if(importedIndex!==null&&!Number.isFinite(importedIndex))errors.push(`Line ${line}: Index is invalid.`);
  if(sourceSpecificGravity!==null&&(!Number.isFinite(sourceSpecificGravity)||sourceSpecificGravity<=0))errors.push(`Line ${line}: Source SG must be greater than zero.`);
  if(!errors.some(error=>error.startsWith(`Line ${line}:`)))rows.push({line,tankShortCode,tankName,maximumVolume,sourceSpecificGravity,point:{volume:volume!,balanceArm:balanceArm!,importedWeight,importedIndex}})
 });
 const seen=new Set<string>();for(const row of rows){const key=`${row.tankShortCode}|${row.point.volume}`;if(seen.has(key))errors.push(`Line ${row.line}: ${row.tankShortCode} Volume ${row.point.volume} is duplicated.`);seen.add(key)}
 return{rows,errors};
}

export function mergeTankCurveImport(current:NonStandardFuelTank[],rows:TankCurveImportRow[]){
 const grouped=new Map<string,TankCurveImportRow[]>();for(const row of rows)grouped.set(row.tankShortCode,[...(grouped.get(row.tankShortCode)??[]),row]);
 const retained=current.filter(tank=>!grouped.has(tank.tankShortCode));
 const imported=[...grouped].map(([code,tankRows])=>{const existing=current.find(tank=>tank.tankShortCode===code),names=[...new Set(tankRows.flatMap(row=>row.tankName?[row.tankName]:[]))],maximums=[...new Set(tankRows.flatMap(row=>row.maximumVolume===null?[]:[row.maximumVolume]))],gravities=[...new Set(tankRows.flatMap(row=>row.sourceSpecificGravity===null?[]:[row.sourceSpecificGravity]))],highestVolume=Math.max(...tankRows.map(row=>row.point.volume));return{tankName:names[0]??existing?.tankName??code,tankShortCode:code,maximumVolume:maximums[0]??existing?.maximumVolume??highestVolume,sourceSpecificGravity:gravities[0]??existing?.sourceSpecificGravity??null,curveSpecificGravities:existing?.curveSpecificGravities??[],indexPerUnitWeight:existing?.indexPerUnitWeight??null,weights:existing?.weights??[],points:tankRows.map(row=>row.point).sort((a,b)=>a.volume-b.volume)}});
 return[...retained,...imported].sort((a,b)=>a.tankShortCode.localeCompare(b.tankShortCode));
}
