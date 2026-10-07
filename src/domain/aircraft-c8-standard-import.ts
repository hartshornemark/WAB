import type {StandardFuelRow} from "./aircraft-c8";
import {csvAircraftIdentityError,csvAircraftIdentityHeaders,normaliseCsvAircraftIdentity,type CsvAircraftIdentity} from "./csv-aircraft-identity";

export type StandardFuelImportResult={rows:StandardFuelRow[];errors:string[];source:CsvAircraftIdentity|null;tableCount:number};

const headers=[...csvAircraftIdentityHeaders,"Configuration Code","Specific Gravity","Fuel Volume","Fuel Weight","H-Arm","Index"];
const tableKey=(row:Pick<StandardFuelRow,"configurationCode"|"specificGravity">)=>`${row.configurationCode??"ALL"}|${row.specificGravity.toFixed(6)}`;
const escape=(value:unknown)=>{const text=String(value??"");return /[",\n]/.test(text)?`"${text.replaceAll('"','""')}"`:text};

export function standardFuelCsvTemplate(typeCode:string,subtype:string,rows:StandardFuelRow[]=[]){
 const identity=[normaliseCsvAircraftIdentity(typeCode),normaliseCsvAircraftIdentity(subtype)];
 const data=rows.filter(row=>row.fuelWeight!==0).sort((a,b)=>(a.configurationCode??"").localeCompare(b.configurationCode??"")||a.specificGravity-b.specificGravity||a.fuelWeight-b.fuelWeight).map(row=>[...identity,row.configurationCode??"ALL",row.specificGravity,row.fuelVolume??"",row.fuelWeight,row.hArm??"",row.indexValue]);
 return [headers,...(data.length?data:[[...identity,"","","","","",""]])].map(row=>row.map(escape).join(",")).join("\n")+"\n";
}

const headerKey=(value:string)=>value.trim().toLowerCase().replace(/[^a-z0-9]/g,"");
const aliases={aircraftType:["aircrafttypeiata"],aircraftSubtype:["seriessubtype"],configurationCode:["configurationcode","fuelconfiguration","fittedconfiguration","configuration"],specificGravity:["specificgravity","sg","fueldensity"],fuelVolume:["fuelvolume","volume","vol"],fuelWeight:["fuelweight","weight","wt"],hArm:["harm","horizontalarm","balancearm"],indexValue:["index","indexvalue"]};
function csvRows(text:string){const rows:string[][]=[];let row:string[]=[],field="",quoted=false;for(let index=0;index<text.length;index++){const char=text[index];if(quoted){if(char==='"'&&text[index+1]==='"'){field+='"';index++}else if(char==='"')quoted=false;else field+=char}else if(char==='"')quoted=true;else if(char===','){row.push(field);field=""}else if(char==='\n'){row.push(field.replace(/\r$/,"").trim());if(row.some(value=>value!==""))rows.push(row);row=[];field=""}else field+=char}row.push(field.replace(/\r$/,"").trim());if(row.some(value=>value!==""))rows.push(row);return rows}
const numeric=(value:string|undefined)=>{if(value===undefined||value.trim()==="")return null;const parsed=Number(value);return Number.isFinite(parsed)?parsed:Number.NaN};

export function parseStandardFuelCsv(text:string,expected:CsvAircraftIdentity,configurationCodes:string[]=[]):StandardFuelImportResult{
 const raw=csvRows(text.replace(/^\uFEFF/,"")),errors:string[]=[],rows:StandardFuelRow[]=[];let source:CsvAircraftIdentity|null=null;
 if(raw.length===0)return{rows,errors:["The CSV file is empty."],source,tableCount:0};
 const normalisedConfigurations=new Set(configurationCodes.map(code=>code.trim().toUpperCase())),reportedInvalidConfigurations=new Set<string>(),head=raw[0].map(headerKey),column=(key:keyof typeof aliases)=>head.findIndex(value=>aliases[key].includes(value)),columns={aircraftType:column("aircraftType"),aircraftSubtype:column("aircraftSubtype"),configurationCode:column("configurationCode"),specificGravity:column("specificGravity"),fuelVolume:column("fuelVolume"),fuelWeight:column("fuelWeight"),hArm:column("hArm"),indexValue:column("indexValue")};
 for(const [key,label] of [["aircraftType",csvAircraftIdentityHeaders[0]],["aircraftSubtype",csvAircraftIdentityHeaders[1]],["configurationCode","Configuration Code"],["specificGravity","Specific Gravity"],["fuelWeight","Fuel Weight"],["indexValue","Index"]] as const)if(columns[key]<0)errors.push(`Missing required column: ${label}.`);
 if(errors.length)return{rows,errors:[...errors,"Download a new Standard Fuel template for this aircraft."],source,tableCount:0};
 raw.slice(1).forEach((values,rowIndex)=>{const line=rowIndex+2,at=(index:number)=>index<0?undefined:values[index],rowSource={typeCode:normaliseCsvAircraftIdentity(at(columns.aircraftType)),subtype:normaliseCsvAircraftIdentity(at(columns.aircraftSubtype))},identityError=csvAircraftIdentityError(rowSource,expected,line),rawConfiguration=String(at(columns.configurationCode)??"").trim().toUpperCase(),configurationCode=!rawConfiguration||rawConfiguration==="ALL"?null:rawConfiguration,specificGravity=numeric(at(columns.specificGravity)),fuelVolume=numeric(at(columns.fuelVolume)),fuelWeight=numeric(at(columns.fuelWeight)),hArm=numeric(at(columns.hArm)),indexValue=numeric(at(columns.indexValue));
  if(identityError)errors.push(identityError);else if(source&&(source.typeCode!==rowSource.typeCode||source.subtype!==rowSource.subtype))errors.push(`Line ${line}: aircraft identity differs from earlier rows.`);else source=rowSource;
  const invalidConfiguration=Boolean(configurationCode&&!normalisedConfigurations.has(configurationCode));if(invalidConfiguration&&!reportedInvalidConfigurations.has(configurationCode!)){errors.push(normalisedConfigurations.size===0?`No fitted fuel configurations are defined for this aircraft. Use ALL or leave Configuration Code blank instead of ${configurationCode}.`:`Configuration Code ${configurationCode} is not defined for this aircraft. Use ALL for a table common to every fitted configuration.`);reportedInvalidConfigurations.add(configurationCode!)}
  if(specificGravity===null||!Number.isFinite(specificGravity)||specificGravity<=0)errors.push(`Line ${line}: Specific Gravity must be greater than zero.`);
  if(fuelVolume!==null&&(!Number.isSafeInteger(fuelVolume)||fuelVolume<=0))errors.push(`Line ${line}: Fuel Volume must be a positive whole number or blank.`);
  if(fuelWeight===null||!Number.isSafeInteger(fuelWeight)||fuelWeight<0)errors.push(`Line ${line}: Fuel Weight must be a whole number of zero or greater.`);
  if(hArm!==null&&!Number.isFinite(hArm))errors.push(`Line ${line}: H-Arm must be a number or blank.`);
  if(indexValue===null||!Number.isFinite(indexValue))errors.push(`Line ${line}: Index is required and must be a number.`);
  if(fuelWeight===0&&indexValue!==0)errors.push(`Line ${line}: a zero Fuel Weight must have a zero Index.`);
  if(!invalidConfiguration&&!errors.some(error=>error.startsWith(`Line ${line}:`)))rows.push({...(configurationCode?{configurationCode}:{}),specificGravity:specificGravity!,fuelVolume,indexValue:indexValue!,fuelWeight:fuelWeight!,hArm});
 });
 const seen=new Map<string,number>();for(const [index,row] of rows.entries()){const key=`${tableKey(row)}|${row.fuelWeight}`,line=index+2;if(seen.has(key))errors.push(`Line ${line}: Fuel Weight ${row.fuelWeight} is duplicated in the same Configuration Code and Specific Gravity table.`);else seen.set(key,line)}
 const groups=new Map<string,StandardFuelRow[]>();for(const row of rows){const key=tableKey(row);groups.set(key,[...(groups.get(key)??[]),row])}
 for(const [key,group] of groups)if(group.filter(row=>row.fuelWeight>0).length<1)errors.push(`${key.replace("|"," · SG ")}: add at least one row above zero Fuel Weight.`);
 return{rows:rows.sort((a,b)=>(a.configurationCode??"").localeCompare(b.configurationCode??"")||a.specificGravity-b.specificGravity||a.fuelWeight-b.fuelWeight),errors,source,tableCount:groups.size};
}

export function mergeStandardFuelImport(current:StandardFuelRow[],imported:StandardFuelRow[]){const keys=new Set(imported.map(tableKey));return[...current.filter(row=>!keys.has(tableKey(row))),...imported]}
