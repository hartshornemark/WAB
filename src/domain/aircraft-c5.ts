export type EnvelopePoint={weight:number;indexValue:number;macValue:number|null};
export type EnvelopeBoundary={fwd:EnvelopePoint[];aft:EnvelopePoint[]};
export type AircraftC5InputMode="INDEX"|"MAC";
export type AircraftC5Section="status"|"mrw"|"towMaximum"|"lawMaximum"|"zfwMaximum"|"tow"|"law"|"zfw";
export type AircraftC5Values={
  curtailed:boolean|null;
  inputMode:AircraftC5InputMode;
  effectiveDow:number;
  effectiveDowSource:"fleet"|"standard"|"unavailable";
  maximumWeights:{mrw:number;tow:number;law:number;zfw:number};
  envelopes:{tow:EnvelopeBoundary;law:EnvelopeBoundary;zfw:EnvelopeBoundary};
};
export type AircraftC5Snapshot={canView:boolean;canEdit:boolean;revision:string;typeCode:string;subtype:string;weightUnit:string;values:AircraftC5Values};
export class AircraftC5Invalid extends Error{}
export class AircraftC5Denied extends Error{}
export class AircraftC5Conflict extends Error{}

export function withAircraftC5Maximum(values:AircraftC5Values,section:"tow"|"law"|"zfw",maximum:number):AircraftC5Values{
  return{...values,maximumWeights:{...values.maximumWeights,[section]:maximum},envelopes:values.envelopes};
}

const finite=(value:unknown,label:string)=>{const n=typeof value==="number"?value:Number(value);if(value===""||value===null||value===undefined||!Number.isFinite(n)||Math.abs(n)>1_000_000_000)throw new AircraftC5Invalid(`Enter a valid ${label}.`);return n};
const weight=(value:unknown,label:string)=>{const n=finite(value,label);if(!Number.isInteger(n)||n<=0)throw new AircraftC5Invalid(`${label} must be a positive whole number.`);return n};
function points(value:unknown,label:string):EnvelopePoint[]{
  if(!Array.isArray(value)||value.length<2)throw new AircraftC5Invalid(`${label} requires at least two points.`);
  const result=value.map((entry,index)=>{const row=entry as Record<string,unknown>;const mac=row.macValue===""||row.macValue===null||row.macValue===undefined?null:finite(row.macValue,`${label} % MAC at row ${index+1}`);if(mac!==null&&(mac<0||mac>100))throw new AircraftC5Invalid(`${label} % MAC must be between 0 and 100.`);return{weight:weight(row.weight,`${label} Weight at row ${index+1}`),indexValue:finite(row.indexValue,`${label} Index at row ${index+1}`),macValue:mac}});
  const seen=new Set<number>();for(const row of result){if(seen.has(row.weight))throw new AircraftC5Invalid(`${label} contains the same Weight more than once.`);seen.add(row.weight)}
  return result.sort((a,b)=>a.weight-b.weight);
}
function progressPoints(value:unknown,label:string,maximum:number):EnvelopePoint[]{
  if(!Array.isArray(value))throw new AircraftC5Invalid(`${label} points are invalid.`);
  const result=value.map((entry,index)=>{const row=entry as Record<string,unknown>;const rowWeight=weight(row.weight,`${label} Weight at row ${index+1}`),indexValue=finite(row.indexValue,`${label} Index at row ${index+1}`),mac=row.macValue===""||row.macValue===null||row.macValue===undefined?null:finite(row.macValue,`${label} % MAC at row ${index+1}`);if(rowWeight>maximum)throw new AircraftC5Invalid(`${label} Weight at row ${index+1} cannot exceed its applicable maximum.`);if(mac!==null&&(mac<0||mac>100))throw new AircraftC5Invalid(`${label} % MAC must be between 0 and 100.`);return{weight:rowWeight,indexValue,macValue:mac}});
  if(new Set(result.map(row=>row.weight)).size!==result.length)throw new AircraftC5Invalid(`${label} contains the same Weight more than once.`);
  return result.sort((a,b)=>a.weight-b.weight);
}

export function validateAircraftC5Section(input:unknown,section:AircraftC5Section):AircraftC5Values{
  const value=input as AircraftC5Values;
  if(!value?.maximumWeights||!value?.envelopes)throw new AircraftC5Invalid("C5.1 data is incomplete.");
  if(section==="status"){if(value.curtailed!==null&&typeof value.curtailed!=="boolean")throw new AircraftC5Invalid("Select Curtailed or Not Curtailed.");if(!["INDEX","MAC"].includes(value.inputMode))throw new AircraftC5Invalid("Select Record Index or Record %MAC.");return value}
  if(section==="mrw"){const result={...value,maximumWeights:{...value.maximumWeights,mrw:weight(value.maximumWeights.mrw,"Maximum Ramp/Taxi Weight")}};validateWeightHierarchy(result.maximumWeights,result.effectiveDow);return result}
  if(section==="towMaximum"||section==="lawMaximum"||section==="zfwMaximum"){const key=section==="towMaximum"?"tow":section==="lawMaximum"?"law":"zfw";const label=key==="tow"?"Maximum Take-Off Weight":key==="law"?"Maximum Landing Weight":"Maximum Zero Fuel Weight";const result=withAircraftC5Maximum(value,key,weight(value.maximumWeights[key],label));validateWeightHierarchy(result.maximumWeights,result.effectiveDow);return result}
  const key=section as "tow"|"law"|"zfw";const maximum=weight(value.maximumWeights[key],key==="tow"?"Maximum Take-Off Weight":key==="law"?"Maximum Landing Weight":"Maximum Zero Fuel Weight");
  const boundary={fwd:progressPoints(value.envelopes[key]?.fwd,`${key.toUpperCase()} FWD`,maximum),aft:progressPoints(value.envelopes[key]?.aft,`${key.toUpperCase()} AFT`,maximum)};
  const result={...value,maximumWeights:{...value.maximumWeights,[key]:maximum},envelopes:{...value.envelopes,[key]:boundary}};validateWeightHierarchy(result.maximumWeights,result.effectiveDow);return result;
}
export function validateAircraftC5(input:unknown):AircraftC5Values{
  const value=input as Record<string,unknown>,max=value?.maximumWeights as Record<string,unknown>,sets=value?.envelopes as Record<string,unknown>;
  const curtailed=value?.curtailed;if(curtailed!==null&&typeof curtailed!=="boolean")throw new AircraftC5Invalid("Select Curtailed or Not Curtailed.");
  const effectiveDow=weight(value?.effectiveDow,"Effective Dry Operating Weight"),effectiveDowSource=value?.effectiveDowSource;if(!["fleet","standard"].includes(String(effectiveDowSource)))throw new AircraftC5Invalid("A fleet DOW or Standard Fleet Weight is required.");
  const inputMode=value?.inputMode;if(!["INDEX","MAC"].includes(String(inputMode)))throw new AircraftC5Invalid("Select Record Index or Record %MAC.");
  const result:AircraftC5Values={curtailed:curtailed as boolean|null,inputMode:inputMode as AircraftC5InputMode,effectiveDow,effectiveDowSource:effectiveDowSource as "fleet"|"standard",maximumWeights:{mrw:weight(max?.mrw,"Maximum Ramp/Taxi Weight"),tow:weight(max?.tow,"Maximum Take-Off Weight"),law:weight(max?.law,"Maximum Landing Weight"),zfw:weight(max?.zfw,"Maximum Zero Fuel Weight")},envelopes:{tow:{fwd:points((sets?.tow as Record<string,unknown>)?.fwd,"Take-Off FWD"),aft:points((sets?.tow as Record<string,unknown>)?.aft,"Take-Off AFT")},law:{fwd:points((sets?.law as Record<string,unknown>)?.fwd,"Landing FWD"),aft:points((sets?.law as Record<string,unknown>)?.aft,"Landing AFT")},zfw:{fwd:points((sets?.zfw as Record<string,unknown>)?.fwd,"Zero Fuel FWD"),aft:points((sets?.zfw as Record<string,unknown>)?.aft,"Zero Fuel AFT")}}};
  for(const key of ["tow","law","zfw"] as const){const maximum=result.maximumWeights[key],boundary=result.envelopes[key];const highest=Math.max(...boundary.fwd.map(row=>row.weight),...boundary.aft.map(row=>row.weight));const fwdCoverage=Math.max(...boundary.fwd.map(row=>row.weight)),aftCoverage=Math.max(...boundary.aft.map(row=>row.weight));if(highest>maximum)throw new AircraftC5Invalid(`A ${key.toUpperCase()} envelope Weight exceeds its applicable maximum.`);if(maximum>fwdCoverage||maximum>aftCoverage)throw new AircraftC5Invalid(`The ${key.toUpperCase()} envelope must cover its applicable maximum Weight.`)}
  validateWeightHierarchy(result.maximumWeights,result.effectiveDow);return result;
}

function validateWeightHierarchy(max:{mrw:number;tow:number;law:number;zfw:number},effectiveDow=0){if(effectiveDow>0&&max.zfw>0&&effectiveDow>max.zfw)throw new AircraftC5Invalid("DOW cannot be greater than MZFW.");if(max.mrw>0&&max.tow>0&&max.tow>max.mrw)throw new AircraftC5Invalid("MTOW cannot be greater than MRW.");if(max.tow>0&&max.law>0&&max.law>max.tow)throw new AircraftC5Invalid("MLAW cannot be greater than MTOW.");if(max.law>0&&max.zfw>0&&max.zfw>max.law)throw new AircraftC5Invalid("MZFW cannot be greater than MLAW.")}
