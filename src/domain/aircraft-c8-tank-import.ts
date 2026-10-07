import type{NonStandardFuelTank,TankFuelPoint}from"./aircraft-c8";
import{csvAircraftIdentityError,csvAircraftIdentityHeaders,normaliseCsvAircraftIdentity,type CsvAircraftIdentity}from"./csv-aircraft-identity";

export type TankCurveImportRow={line:number;configurationCode:string|null;tankShortCode:string;tankName:string|null;maximumVolume:number|null;sourceSpecificGravity:number|null;point:TankFuelPoint};
export type TankCurveImportResult={rows:TankCurveImportRow[];errors:string[];source:CsvAircraftIdentity|null};

export const tankCurveCsvTemplate=(typeCode:string,subtype:string,includeBlank=true)=>`${csvAircraftIdentityHeaders.join(",")},Configuration Code,Tank Code,Tank Name,Maximum Volume,Volume,Balance Arm,Weight,Index,Source SG\n${includeBlank?`${normaliseCsvAircraftIdentity(typeCode)},${normaliseCsvAircraftIdentity(subtype)},,,,,,,,\n`:""}`;

const headerKey=(value:string)=>value.trim().toLowerCase().replace(/[^a-z0-9]/g,"");
const aliases:Record<string,string[]>={aircraftType:["aircrafttypeiata"],aircraftSubtype:["seriessubtype"],configurationCode:["configurationcode","fuelconfiguration","configuration"],tankShortCode:["tankcode","tankshortcode","tank"],tankName:["tankname","name"],maximumVolume:["maximumvolume","maxvolume","tankmaximumvolume"],volume:["volume","fuelvolume"],balanceArm:["balancearm","arm","harm"],importedWeight:["weight","fuelweight"],importedIndex:["index","indexvalue"],sourceSpecificGravity:["sourcesg","specificgravity","sg","fueldensity"]};

function csvRows(text:string){const rows:string[][]=[];let row:string[]=[],field="",quoted=false;for(let index=0;index<text.length;index++){const char=text[index];if(quoted){if(char==='"'&&text[index+1]==='"'){field+='"';index++}else if(char==='"')quoted=false;else field+=char}else if(char==='"')quoted=true;else if(char===','){row.push(field);field=""}else if(char==='\n'){row.push(field.replace(/\r$/,"").trim());if(row.some(value=>value!==""))rows.push(row);row=[];field=""}else field+=char}row.push(field.replace(/\r$/,"").trim());if(row.some(value=>value!==""))rows.push(row);return rows}
const number=(value:string|undefined)=>{if(value===undefined||value.trim()==="")return null;const result=Number(value);return Number.isFinite(result)?result:Number.NaN};

export function parseTankCurveCsv(text:string,expected?:CsvAircraftIdentity,configurationCodes:string[]=[]):TankCurveImportResult{
 const raw=csvRows(text.replace(/^\uFEFF/,"")),errors:string[]=[],rows:TankCurveImportRow[]=[];let source:CsvAircraftIdentity|null=null;
 if(raw.length===0)return{rows,errors:["The CSV file is empty."],source};
 const normalisedConfigurations=new Set(configurationCodes.map(code=>code.trim().toUpperCase())),reportedInvalidConfigurations=new Set<string>();
 const headers=raw[0].map(headerKey),columns=Object.fromEntries(Object.entries(aliases).map(([key,names])=>[key,headers.findIndex(header=>names.includes(header))])) as Record<keyof typeof aliases,number>;
 for(const required of ["tankShortCode","volume","balanceArm"] as const)if(columns[required]<0)errors.push(`Missing required column: ${required==="tankShortCode"?"Tank Code":required==="balanceArm"?"Balance Arm":"Volume"}.`);
 if(expected){if(columns.aircraftType<0)errors.push(`Missing required column: ${csvAircraftIdentityHeaders[0]}.`);if(columns.aircraftSubtype<0)errors.push(`Missing required column: ${csvAircraftIdentityHeaders[1]}.`)}
 if(errors.length)return{rows,errors:[...errors,...(expected?["Download a new template for this aircraft."]:[])],source};
 raw.slice(1).forEach((values,rowIndex)=>{const line=rowIndex+2,at=(key:keyof typeof aliases)=>columns[key]<0?undefined:values[columns[key]],rowSource={typeCode:normaliseCsvAircraftIdentity(at("aircraftType")),subtype:normaliseCsvAircraftIdentity(at("aircraftSubtype"))},rawConfiguration=String(at("configurationCode")??"").trim().toUpperCase(),configurationCode=!rawConfiguration||rawConfiguration==="ALL"?null:rawConfiguration,tankShortCode=String(at("tankShortCode")??"").trim().toUpperCase(),tankName=String(at("tankName")??"").trim()||null,maximumVolume=number(at("maximumVolume")),volume=number(at("volume")),balanceArm=number(at("balanceArm")),importedWeight=number(at("importedWeight")),importedIndex=number(at("importedIndex")),sourceSpecificGravity=number(at("sourceSpecificGravity"));
  if(expected){const identityError=csvAircraftIdentityError(rowSource,expected,line);if(identityError)errors.push(identityError);else if(source&&(source.typeCode!==rowSource.typeCode||source.subtype!==rowSource.subtype))errors.push(`Line ${line}: aircraft identity differs from earlier rows.`);else source=rowSource}
  const invalidConfiguration=Boolean(configurationCode&&!normalisedConfigurations.has(configurationCode));if(invalidConfiguration&&!reportedInvalidConfigurations.has(configurationCode!)){errors.push(normalisedConfigurations.size===0?`No fitted fuel configurations are defined for this aircraft. Use ALL or leave Configuration Code blank instead of ${configurationCode}.`:`Configuration Code ${configurationCode} is not defined on E1.2 for this aircraft. Use ALL for a curve common to every fitted configuration.`);reportedInvalidConfigurations.add(configurationCode!)}
  if(!/^[A-Z0-9]{1,6}$/.test(tankShortCode))errors.push(`Line ${line}: Tank Code must contain one to six letters or numbers.`);
  if(volume===null||!Number.isSafeInteger(volume)||volume<0)errors.push(`Line ${line}: Volume must be a whole number of zero or greater.`);
  if(balanceArm===null||!Number.isFinite(balanceArm))errors.push(`Line ${line}: Balance Arm is required.`);
  if(maximumVolume!==null&&(!Number.isSafeInteger(maximumVolume)||maximumVolume<=0))errors.push(`Line ${line}: Maximum Volume must be a positive whole number.`);
  if(importedWeight!==null&&(!Number.isSafeInteger(importedWeight)||importedWeight<0))errors.push(`Line ${line}: Weight must be a whole number of zero or greater.`);
  if(importedIndex!==null&&!Number.isFinite(importedIndex))errors.push(`Line ${line}: Index is invalid.`);
  if(sourceSpecificGravity!==null&&(!Number.isFinite(sourceSpecificGravity)||sourceSpecificGravity<=0))errors.push(`Line ${line}: Source SG must be greater than zero.`);
  if(!invalidConfiguration&&!errors.some(error=>error.startsWith(`Line ${line}:`)))rows.push({line,configurationCode,tankShortCode,tankName,maximumVolume,sourceSpecificGravity,point:{volume:volume!,balanceArm:balanceArm!,importedWeight,importedIndex}})
 });
 const seen=new Set<string>();for(const row of rows){const key=`${row.configurationCode??"ALL"}|${row.tankShortCode}|${row.point.volume}`;if(seen.has(key))errors.push(`Line ${row.line}: ${row.tankShortCode} Volume ${row.point.volume} is duplicated.`);seen.add(key)}
 return{rows,errors,source};
}

export function mergeTankCurveImport(current:NonStandardFuelTank[],rows:TankCurveImportRow[]){
 const grouped=new Map<string,TankCurveImportRow[]>();for(const row of rows)grouped.set(`${row.configurationCode??"ALL"}|${row.tankShortCode}`,[...(grouped.get(`${row.configurationCode??"ALL"}|${row.tankShortCode}`)??[]),row]);
 const retained=current.filter(tank=>!grouped.has(`${tank.configurationCode??"ALL"}|${tank.tankShortCode}`));
 const imported=[...grouped].map(([,tankRows])=>{const code=tankRows[0].tankShortCode,configurationCode=tankRows[0].configurationCode,existing=current.find(tank=>tank.tankShortCode===code&&(tank.configurationCode??null)===configurationCode),names=[...new Set(tankRows.flatMap(row=>row.tankName?[row.tankName]:[]))],maximums=[...new Set(tankRows.flatMap(row=>row.maximumVolume===null?[]:[row.maximumVolume]))],gravities=[...new Set(tankRows.flatMap(row=>row.sourceSpecificGravity===null?[]:[row.sourceSpecificGravity]))],highestVolume=Math.max(...tankRows.map(row=>row.point.volume));return{...(configurationCode?{configurationCode}:{}),tankName:names[0]??existing?.tankName??code,tankShortCode:code,maximumVolume:maximums[0]??existing?.maximumVolume??highestVolume,sourceSpecificGravity:gravities[0]??existing?.sourceSpecificGravity??null,curveSpecificGravities:existing?.curveSpecificGravities??[],indexPerUnitWeight:existing?.indexPerUnitWeight??null,weights:existing?.weights??[],points:tankRows.map(row=>row.point).sort((a,b)=>a.volume-b.volume)}});
 return[...retained,...imported].sort((a,b)=>a.tankShortCode.localeCompare(b.tankShortCode));
}
