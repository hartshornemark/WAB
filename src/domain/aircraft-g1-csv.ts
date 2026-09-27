import type{AircraftG1Snapshot,G1CompatibilityRow}from"@/domain/aircraft-g1";

export type AircraftG1CsvResult={rows:G1CompatibilityRow[];errors:string[];identityCount:number;bayCount:number};

function csvRows(text:string){const rows:string[][]=[];let row:string[]=[],cell="",quoted=false;for(let i=0;i<text.length;i+=1){const c=text[i];if(quoted){if(c==='"'&&text[i+1]==='"'){cell+='"';i+=1}else if(c==='"')quoted=false;else cell+=c}else if(c==='"')quoted=true;else if(c===","){row.push(cell);cell=""}else if(c==="\n"){row.push(cell);rows.push(row);row=[];cell=""}else if(c!=="\r")cell+=c}row.push(cell);if(row.some(x=>x.trim()))rows.push(row);return rows}
const clean=(v:string|undefined)=>String(v??"").trim();
const key=(v:string)=>clean(v).toUpperCase().replace(/[^A-Z0-9-]/g,"");
const headerKey=(v:string)=>clean(v).toLowerCase().replace(/[^a-z0-9]/g,"");
const answer=(v:string|undefined)=>{const n=clean(v).toUpperCase();if(["Y","YES","TRUE","1"].includes(n))return true;if(["N","NO","FALSE","0"].includes(n))return false;return null};

export function aircraftG1CsvTemplate(snapshot:AircraftG1Snapshot){
  const identities=snapshot.uldIdentities.length?snapshot.uldIdentities:snapshot.uldTypes.map(type=>({code:type,type}));
  const lines=[["Position Bay",...identities.map(x=>x.code)],...snapshot.bays.map(bay=>[bay.bayId,...identities.map(()=>"")])];
  return lines.map(row=>row.join(",")).join("\r\n");
}

export function parseAircraftG1Csv(text:string,snapshot:AircraftG1Snapshot):AircraftG1CsvResult{
  const records=csvRows(text.replace(/^\uFEFF/,"")),errors:string[]=[];
  if(!records.length)return{rows:[],errors:["The CSV file is empty."],identityCount:0,bayCount:0};
  const header=records[0],positionIndex=header.findIndex(value=>["positionbay","position","bay"].includes(headerKey(value)));
  if(positionIndex<0)return{rows:[],errors:["Missing Position Bay column."],identityCount:0,bayCount:0};
  const identities=snapshot.uldIdentities.length?snapshot.uldIdentities:snapshot.uldTypes.map(type=>({code:type,type}));
  const byCode=new Map(identities.map(identity=>[key(identity.code),identity.type]));
  for(const type of snapshot.uldTypes)byCode.set(key(type),type);
  const columns=header.map((value,index)=>({index,code:key(value),type:byCode.get(key(value))})).filter(column=>column.index!==positionIndex&&column.code);
  const unknown=columns.filter(column=>!column.type).map(column=>header[column.index]);
  if(unknown.length)errors.push(`Unknown B5 ULD columns: ${unknown.join(", ")}.`);
  const known=columns.filter((column):column is typeof column&{type:string}=>Boolean(column.type));
  for(const type of snapshot.uldTypes)if(!known.some(column=>column.type===type))errors.push(`No CSV column represents B5 ULD Type ${type}.`);
  const expectedBays=new Set(snapshot.bays.map(bay=>bay.bayId.toUpperCase())),seen=new Set<string>(),rows:G1CompatibilityRow[]=[];
  records.slice(1).forEach((record,index)=>{const line=index+2,bayId=clean(record[positionIndex]).toUpperCase();if(!bayId)return;if(!expectedBays.has(bayId)){errors.push(`Line ${line}: Bay ${bayId} is not configured on D3.`);return}if(seen.has(bayId)){errors.push(`Line ${line}: Bay ${bayId} is duplicated.`);return}seen.add(bayId);for(const type of snapshot.uldTypes){const typeColumns=known.filter(column=>column.type===type),values=typeColumns.map(column=>answer(record[column.index]));if(values.some(value=>value===null)){errors.push(`Line ${line}: enter Y or N for ${typeColumns.filter((_,i)=>values[i]===null).map(column=>header[column.index]).join(", ")}.`);continue}if(new Set(values).size>1){errors.push(`Line ${line}: ${typeColumns.map(column=>header[column.index]).join(" / ")} disagree for ${type}.`);continue}rows.push({bayId,uldType:type,compatible:values[0]??null})}});
  const missing=[...expectedBays].filter(bay=>!seen.has(bay));if(missing.length)errors.push(`Missing D3 Bays: ${missing.join(", ")}.`);
  return{rows,errors:[...new Set(errors)],identityCount:known.length,bayCount:seen.size};
}
