import type{FuelLoadingSchedule,FuelScheduleQuantityBasis}from"./aircraft-c8";

export type ScheduleImportResult={schedules:FuelLoadingSchedule[];errors:string[]};

export const scheduleCsvTemplate="Configuration Code,Schedule Name,Specific Gravity,Step,Tank Code(s),Volume Amount,Weight Amount\n";

const headerKey=(value:string)=>value.trim().toLowerCase().replace(/[^a-z0-9]/g,"");
const aliases={configurationCode:["configurationcode","fuelconfiguration","configuration"],name:["schedulename","distributionname","name"],specificGravity:["specificgravity","sg","fueldensity"],step:["step","stepnumber","sequence"],tankCodes:["tankcodes","tankcode","tanknames","tankname","tanks"],volume:["volumeamount","volume","vol"],weight:["weightamount","weight","wt"]};

function csvRows(text:string){const rows:string[][]=[];let row:string[]=[],field="",quoted=false;for(let index=0;index<text.length;index++){const char=text[index];if(quoted){if(char==='"'&&text[index+1]==='"'){field+='"';index++}else if(char==='"')quoted=false;else field+=char}else if(char==='"')quoted=true;else if(char===','){row.push(field);field=""}else if(char==='\n'){row.push(field.replace(/\r$/,"").trim());if(row.some(value=>value!==""))rows.push(row);row=[];field=""}else field+=char}row.push(field.replace(/\r$/,"").trim());if(row.some(value=>value!==""))rows.push(row);return rows}
const numeric=(value:string|undefined)=>{if(value===undefined||value.trim()==="")return null;const parsed=Number(value);return Number.isFinite(parsed)?parsed:Number.NaN};

export function parseScheduleCsv(text:string):ScheduleImportResult{
 const raw=csvRows(text.replace(/^\uFEFF/,"")),errors:string[]=[];
 if(raw.length===0)return{schedules:[],errors:["The CSV file is empty."]};
 const headers=raw[0].map(headerKey),column=(key:keyof typeof aliases)=>headers.findIndex(header=>aliases[key].includes(header)),columns={configurationCode:column("configurationCode"),name:column("name"),specificGravity:column("specificGravity"),step:column("step"),tankCodes:column("tankCodes"),volume:column("volume"),weight:column("weight")};
 for(const [key,label] of [["name","Schedule Name"],["specificGravity","Specific Gravity"],["step","Step"],["tankCodes","Tank Code(s)"]] as const)if(columns[key]<0)errors.push(`Missing required column: ${label}.`);
 if(columns.volume<0&&columns.weight<0)errors.push("Include at least one of Volume Amount or Weight Amount.");
 if(errors.length)return{schedules:[],errors};
 type Parsed={line:number;configurationCode:string|null;name:string;specificGravity:number;step:number;tankCodes:string[];basis:FuelScheduleQuantityBasis;amount:number};const parsed:Parsed[]=[];
 raw.slice(1).forEach((values,rowIndex)=>{const line=rowIndex+2,at=(index:number)=>index<0?undefined:values[index],configurationCode=String(at(columns.configurationCode)??"").trim().toUpperCase()||null,name=String(at(columns.name)??"").trim(),specificGravity=numeric(at(columns.specificGravity)),step=numeric(at(columns.step)),tankCodes=String(at(columns.tankCodes)??"").split(/[+;|/]/).map(code=>code.trim().toUpperCase()).filter(Boolean),volume=numeric(at(columns.volume)),weight=numeric(at(columns.weight));
  if(!name||name.length>100)errors.push(`Line ${line}: Schedule Name is required and may contain up to 100 characters.`);
  if(specificGravity===null||!Number.isFinite(specificGravity)||specificGravity<=0)errors.push(`Line ${line}: Specific Gravity must be greater than zero.`);
  if(step===null||!Number.isSafeInteger(step)||step<=0)errors.push(`Line ${line}: Step must be a positive whole number.`);
  if(tankCodes.length===0)errors.push(`Line ${line}: enter at least one Tank Code.`);else for(const code of tankCodes)if(!/^[A-Z0-9]{1,6}$/.test(code))errors.push(`Line ${line}: Tank Code ${code} must contain one to six letters or numbers.`);
  const hasVolume=volume!==null,hasWeight=weight!==null;if(hasVolume===hasWeight)errors.push(`Line ${line}: complete either Volume Amount or Weight Amount, but not both.`);
  const amount=hasVolume?volume:weight,basis:FuelScheduleQuantityBasis=hasVolume?"VOLUME":"WEIGHT";if(amount===null||!Number.isFinite(amount)||amount<=0)errors.push(`Line ${line}: the selected Amount must be greater than zero.`);
  if(!errors.some(error=>error.startsWith(`Line ${line}:`)))parsed.push({line,configurationCode,name,specificGravity:specificGravity!,step:step!,tankCodes:[...new Set(tankCodes)],basis,amount:amount!})
 });
 const groups=new Map<string,Parsed[]>();for(const row of parsed){const key=`${row.configurationCode??"ALL"}|${row.name}|${row.specificGravity}`;groups.set(key,[...(groups.get(key)??[]),row])}
 const schedules:FuelLoadingSchedule[]=[];for(const rows of groups.values()){const first=rows[0],bases=new Set(rows.map(row=>row.basis)),steps=rows.map(row=>row.step).sort((a,b)=>a-b);if(bases.size>1)errors.push(`${first.name}: use Volume Amount or Weight Amount consistently for every step.`);if(new Set(steps).size!==steps.length)errors.push(`${first.name}: each Step number may appear only once.`);if(steps.some((step,index)=>step!==index+1))errors.push(`${first.name}: Steps must run consecutively from 1.`);schedules.push({...(first.configurationCode?{configurationCode:first.configurationCode}:{}),name:first.name,specificGravity:first.specificGravity,quantityBasis:first.basis,steps:rows.sort((a,b)=>a.step-b.step).map(row=>({amount:row.amount,tankCodes:row.tankCodes}))})}
 return{schedules,errors};
}

export function mergeScheduleImport(current:FuelLoadingSchedule[],imported:FuelLoadingSchedule[]){const keys=new Set(imported.map(schedule=>`${schedule.configurationCode??"ALL"}|${schedule.name.toUpperCase()}|${schedule.specificGravity}`));return[...current.filter(schedule=>!keys.has(`${schedule.configurationCode??"ALL"}|${schedule.name.toUpperCase()}|${schedule.specificGravity}`)),...imported]}
