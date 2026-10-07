import type{AircraftC11MatrixRow,AircraftC11Values}from"./aircraft-c11";
import{csvAircraftIdentityError,csvAircraftIdentityHeaders,normaliseCsvAircraftIdentity,type CsvAircraftIdentity}from"./csv-aircraft-identity";

export type C11MatrixImportResult={macColumns:number[];rows:AircraftC11MatrixRow[];errors:string[];source:CsvAircraftIdentity|null;valueCount:number};
const headings=[...csvAircraftIdentityHeaders,"Actual TOW","%MAC","Stabiliser Trim"];
const escape=(value:unknown)=>{const text=String(value??"");return /[",\n]/.test(text)?`"${text.replaceAll('"','""')}"`:text};
export function c11MatrixCsvTemplate(typeCode:string,subtype:string,values?:AircraftC11Values){const identity=[normaliseCsvAircraftIdentity(typeCode),normaliseCsvAircraftIdentity(subtype)],data=values?.method==="MATRIX"?values.rows.flatMap(row=>values.macColumns.map((mac,index)=>[...identity,row.tow,mac,row.trimValues[index]??""])):[];return[headings,...(data.length?data:[[...identity,"","",""]])].map(row=>row.map(escape).join(",")).join("\n")+"\n"}
const headerKey=(value:string)=>value.trim().toLowerCase().replace(/[^a-z0-9]/g,"");
const aliases={aircraftType:["aircrafttypeiata"],aircraftSubtype:["seriessubtype"],tow:["actualtow","acttow","tow"],mac:["mac","percentmac","cgpercentmac","aircraftcg"],trim:["stabilisertrim","stabilizertrim","trim","stab"]};
function csvRows(text:string){const rows:string[][]=[];let row:string[]=[],field="",quoted=false;for(let index=0;index<text.length;index++){const char=text[index];if(quoted){if(char==='"'&&text[index+1]==='"'){field+='"';index++}else if(char==='"')quoted=false;else field+=char}else if(char==='"')quoted=true;else if(char===','){row.push(field);field=""}else if(char==='\n'){row.push(field.replace(/\r$/,"").trim());if(row.some(value=>value!==""))rows.push(row);row=[];field=""}else field+=char}row.push(field.replace(/\r$/,"").trim());if(row.some(value=>value!==""))rows.push(row);return rows}
const numeric=(value:string|undefined)=>{if(value===undefined||value.trim()==="")return null;const parsed=Number(value);return Number.isFinite(parsed)?parsed:Number.NaN};
export function parseC11MatrixCsv(text:string,expected:CsvAircraftIdentity):C11MatrixImportResult{
 const raw=csvRows(text.replace(/^\uFEFF/,"")),errors:string[]=[],points:{line:number;tow:number;mac:number;trim:number|null}[]=[];let source:CsvAircraftIdentity|null=null;
 if(raw.length===0)return{macColumns:[],rows:[],errors:["The CSV file is empty."],source,valueCount:0};
 const head=raw[0].map(headerKey),column=(key:keyof typeof aliases)=>head.findIndex(value=>aliases[key].includes(value)),columns={aircraftType:column("aircraftType"),aircraftSubtype:column("aircraftSubtype"),tow:column("tow"),mac:column("mac"),trim:column("trim")};
 for(const [key,label]of[["aircraftType",csvAircraftIdentityHeaders[0]],["aircraftSubtype",csvAircraftIdentityHeaders[1]],["tow","Actual TOW"],["mac","%MAC"],["trim","Stabiliser Trim"]]as const)if(columns[key]<0)errors.push(`Missing required column: ${label}.`);
 if(errors.length)return{macColumns:[],rows:[],errors:[...errors,"Download a new C11.1 matrix template for this aircraft."],source,valueCount:0};
 raw.slice(1).forEach((values,rowIndex)=>{const line=rowIndex+2,at=(index:number)=>values[index],rowSource={typeCode:normaliseCsvAircraftIdentity(at(columns.aircraftType)),subtype:normaliseCsvAircraftIdentity(at(columns.aircraftSubtype))},identityError=csvAircraftIdentityError(rowSource,expected,line),tow=numeric(at(columns.tow)),mac=numeric(at(columns.mac)),trimText=String(at(columns.trim)??"").trim(),trim=trimText===""||trimText==="-"?null:numeric(trimText);
  if(identityError)errors.push(identityError);else if(source&&(source.typeCode!==rowSource.typeCode||source.subtype!==rowSource.subtype))errors.push(`Line ${line}: aircraft identity differs from earlier rows.`);else source=rowSource;
  if(tow===null||!Number.isSafeInteger(tow)||tow<=0)errors.push(`Line ${line}: Actual TOW must be a positive whole number.`);
  if(mac===null||!Number.isFinite(mac))errors.push(`Line ${line}: %MAC is required.`);
  if(trim!==null&&!Number.isFinite(trim))errors.push(`Line ${line}: Stabiliser Trim must be a number, blank or -.`);
  if(!errors.some(error=>error.startsWith(`Line ${line}:`)))points.push({line,tow:tow!,mac:mac!,trim});
 });
 const seen=new Set<string>();for(const point of points){const key=`${point.tow}|${point.mac}`;if(seen.has(key))errors.push(`Line ${point.line}: Actual TOW ${point.tow} and ${point.mac}% MAC is duplicated.`);seen.add(key)}
 const macColumns=[...new Set(points.map(point=>point.mac))].sort((a,b)=>a-b),tows=[...new Set(points.map(point=>point.tow))].sort((a,b)=>a-b),lookup=new Map(points.map(point=>[`${point.tow}|${point.mac}`,point.trim])),rows=tows.map(tow=>({tow,trimValues:macColumns.map(mac=>lookup.get(`${tow}|${mac}`)??null)})),valueCount=points.filter(point=>point.trim!==null).length;
 if(macColumns.length<2)errors.push("Include at least two different %MAC values.");if(rows.length<2)errors.push("Include at least two different Actual TOW values.");
 for(const row of rows)if(row.trimValues.filter(value=>value!==null).length<2)errors.push(`Actual TOW ${row.tow}: enter at least two stabiliser values.`);
 for(let column=0;column<macColumns.length;column++)if(!rows.some(row=>row.trimValues[column]!==null))errors.push(`${macColumns[column]}% MAC: enter at least one stabiliser value.`);
 return{macColumns,rows,errors,source,valueCount};
}
