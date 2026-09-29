export type EnvelopePoint={weight:number;indexValue:number;macValue:number|null};
export type EnvelopeBoundary={fwd:EnvelopePoint[];aft:EnvelopePoint[]};
export type AircraftC5Phase="tow"|"law"|"zfw";
export type AircraftC5EnvelopeMode="STANDARD"|"CONDITIONAL";
export type EnvelopeConditionBasis="TAKE_OFF_FUEL"|"LANDING_FUEL"|"OTHER";
export type ConditionalEnvelope={id:string;code:string;conditionBasis:EnvelopeConditionBasis;conditionDescription:string;lowerBound:number|null;lowerInclusive:boolean;upperBound:number|null;upperInclusive:boolean;boundary:EnvelopeBoundary};
export type AircraftC5InputMode="INDEX"|"MAC";
export type AircraftC5Section="status"|"mrw"|"towMaximum"|"lawMaximum"|"zfwMaximum"|"tow"|"law"|"zfw";
export type AircraftC5Values={
  curtailed:boolean|null;
  inputMode:AircraftC5InputMode;
  effectiveDow:number;
  effectiveDowSource:"fleet"|"standard"|"unavailable";
  maximumWeights:{mrw:number;tow:number;law:number;zfw:number};
  envelopes:{tow:EnvelopeBoundary;law:EnvelopeBoundary;zfw:EnvelopeBoundary};
  envelopeModes?:Record<AircraftC5Phase,AircraftC5EnvelopeMode>;
  conditionalEnvelopes?:Record<AircraftC5Phase,ConditionalEnvelope[]>;
};
export type AircraftC5Snapshot={canView:boolean;canEdit:boolean;revision:string;typeCode:string;subtype:string;weightUnit:string;values:AircraftC5Values};
export class AircraftC5Invalid extends Error{}
export class AircraftC5Denied extends Error{}
export class AircraftC5Conflict extends Error{}

export function withAircraftC5Maximum(values:AircraftC5Values,section:"tow"|"law"|"zfw",maximum:number):AircraftC5Values{
  const conditionalEnvelopes=structuredClone(values.conditionalEnvelopes??emptyConditionalEnvelopes());
  if(Number.isFinite(maximum)&&maximum>0)for(const variant of conditionalEnvelopes[section])for(const side of ["fwd","aft"] as const)variant.boundary[side]=variant.boundary[side].filter(point=>point.weight<=maximum);
  return{...values,maximumWeights:{...values.maximumWeights,[section]:maximum},envelopes:values.envelopes,conditionalEnvelopes};
}

export const emptyConditionalEnvelopes=():Record<AircraftC5Phase,ConditionalEnvelope[]>=>({tow:[],law:[],zfw:[]});
export const envelopeMode=(values:AircraftC5Values,phase:AircraftC5Phase):AircraftC5EnvelopeMode=>values.envelopeModes?.[phase]??"STANDARD";
export const conditionalEnvelopes=(values:AircraftC5Values,phase:AircraftC5Phase):ConditionalEnvelope[]=>values.conditionalEnvelopes?.[phase]??[];
export const conditionBandsMeet=(previous:ConditionalEnvelope,current:ConditionalEnvelope)=>{
  if(previous.upperBound===null||current.lowerBound===null)return false;
  const sharedBoundary=previous.upperBound===current.lowerBound&&previous.upperInclusive!==current.lowerInclusive;
  const consecutiveWholeWeights=Number.isSafeInteger(previous.upperBound)&&Number.isSafeInteger(current.lowerBound)&&current.lowerBound===previous.upperBound+1&&previous.upperInclusive&&current.lowerInclusive;
  return sharedBoundary||consecutiveWholeWeights;
};

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

const nullableBound=(value:unknown,label:string)=>value===""||value===null||value===undefined?null:weight(value,label);
function progressConditionalEnvelopes(value:unknown,phase:AircraftC5Phase,maximum:number):ConditionalEnvelope[]{
  if(!Array.isArray(value))throw new AircraftC5Invalid(`${phase.toUpperCase()} conditional envelopes are invalid.`);
  const codes=new Set<string>();
  return value.map((entry,index)=>{
    const row=entry as Record<string,unknown>,code=String(row.code??"").trim().toUpperCase(),basis=String(row.conditionBasis??"") as EnvelopeConditionBasis,description=String(row.conditionDescription??"").trim(),lower=nullableBound(row.lowerBound,`condition ${index+1} lower limit`),upper=nullableBound(row.upperBound,`condition ${index+1} upper limit`);
    if(!code)throw new AircraftC5Invalid(`Enter a code for conditional envelope ${index+1}.`);if(codes.has(code))throw new AircraftC5Invalid(`Conditional envelope code ${code} is duplicated.`);codes.add(code);
    if(!["TAKE_OFF_FUEL","LANDING_FUEL","OTHER"].includes(basis))throw new AircraftC5Invalid(`Select the condition for ${code}.`);
    if(basis==="OTHER"&&!description)throw new AircraftC5Invalid(`Describe the operational condition for ${code}.`);
    if(lower!==null&&upper!==null&&lower>=upper)throw new AircraftC5Invalid(`${code} lower condition limit must be below its upper limit.`);
    const source=row.boundary as Record<string,unknown>;
    return{id:String(row.id??""),code,conditionBasis:basis,conditionDescription:description,lowerBound:lower,lowerInclusive:Boolean(row.lowerInclusive),upperBound:upper,upperInclusive:Boolean(row.upperInclusive),boundary:{fwd:progressPoints(source?.fwd,`${phase.toUpperCase()} ${code} FWD`,maximum),aft:progressPoints(source?.aft,`${phase.toUpperCase()} ${code} AFT`,maximum)}};
  });
}
function completeConditionalEnvelopes(value:unknown,phase:AircraftC5Phase,maximum:number){
  const variants=progressConditionalEnvelopes(value,phase,maximum);
  if(variants.length<2)throw new AircraftC5Invalid(`${phase.toUpperCase()} conditional mode requires at least two complete envelopes.`);
  const basis=variants[0].conditionBasis;if(variants.some(item=>item.conditionBasis!==basis))throw new AircraftC5Invalid(`${phase.toUpperCase()} conditional envelopes must use the same condition.`);
  for(const item of variants){item.boundary={fwd:points(item.boundary.fwd,`${phase.toUpperCase()} ${item.code} FWD`),aft:points(item.boundary.aft,`${phase.toUpperCase()} ${item.code} AFT`)};for(const side of ["fwd","aft"] as const)if(item.boundary[side].at(-1)?.weight!==maximum)throw new AircraftC5Invalid(`${phase.toUpperCase()} ${item.code} ${side.toUpperCase()} must end at its applicable maximum Weight.`)}
  if(basis!=="OTHER"){
    const ordered=[...variants].sort((a,b)=>(a.lowerBound??-1)-(b.lowerBound??-1));
    if(ordered[0].lowerBound!==null||ordered.at(-1)?.upperBound!==null)throw new AircraftC5Invalid(`${phase.toUpperCase()} fuel bands must cover every possible value.`);
    for(let index=1;index<ordered.length;index++){const previous=ordered[index-1],current=ordered[index];if(!conditionBandsMeet(previous,current))throw new AircraftC5Invalid(`${phase.toUpperCase()} fuel bands must meet without gaps or overlaps.`)}
  }
  return variants;
}

export function validateAircraftC5Section(input:unknown,section:AircraftC5Section):AircraftC5Values{
  const value=input as AircraftC5Values;
  if(!value?.maximumWeights||!value?.envelopes)throw new AircraftC5Invalid("C5.1 data is incomplete.");
  if(section==="status"){if(value.curtailed!==null&&typeof value.curtailed!=="boolean")throw new AircraftC5Invalid("Select Curtailed or Not Curtailed.");if(!["INDEX","MAC"].includes(value.inputMode))throw new AircraftC5Invalid("Select Record Index or Record %MAC.");return value}
  if(section==="mrw"){const result={...value,maximumWeights:{...value.maximumWeights,mrw:weight(value.maximumWeights.mrw,"Maximum Ramp/Taxi Weight")}};validateWeightHierarchy(result.maximumWeights,result.effectiveDow);return result}
  if(section==="towMaximum"||section==="lawMaximum"||section==="zfwMaximum"){const key=section==="towMaximum"?"tow":section==="lawMaximum"?"law":"zfw";const label=key==="tow"?"Maximum Take-Off Weight":key==="law"?"Maximum Landing Weight":"Maximum Zero Fuel Weight";const result=withAircraftC5Maximum(value,key,weight(value.maximumWeights[key],label));validateWeightHierarchy(result.maximumWeights,result.effectiveDow);return result}
  const key=section as AircraftC5Phase;const maximum=weight(value.maximumWeights[key],key==="tow"?"Maximum Take-Off Weight":key==="law"?"Maximum Landing Weight":"Maximum Zero Fuel Weight"),mode=envelopeMode(value,key);
  if(mode==="CONDITIONAL"){
    const variants=progressConditionalEnvelopes(conditionalEnvelopes(value,key),key,maximum),result={...value,envelopeModes:{tow:envelopeMode(value,"tow"),law:envelopeMode(value,"law"),zfw:envelopeMode(value,"zfw"),[key]:mode},conditionalEnvelopes:{...emptyConditionalEnvelopes(),...value.conditionalEnvelopes,[key]:variants}};validateWeightHierarchy(result.maximumWeights,result.effectiveDow);return result;
  }
  const boundary={fwd:progressPoints(value.envelopes[key]?.fwd,`${key.toUpperCase()} FWD`,maximum),aft:progressPoints(value.envelopes[key]?.aft,`${key.toUpperCase()} AFT`,maximum)};
  const result={...value,envelopeModes:{tow:envelopeMode(value,"tow"),law:envelopeMode(value,"law"),zfw:envelopeMode(value,"zfw"),[key]:mode},maximumWeights:{...value.maximumWeights,[key]:maximum},envelopes:{...value.envelopes,[key]:boundary}};validateWeightHierarchy(result.maximumWeights,result.effectiveDow);return result;
}
export function validateAircraftC5(input:unknown):AircraftC5Values{
  const value=input as Record<string,unknown>,max=value?.maximumWeights as Record<string,unknown>,sets=value?.envelopes as Record<string,unknown>;
  const curtailed=value?.curtailed;if(curtailed!==null&&typeof curtailed!=="boolean")throw new AircraftC5Invalid("Select Curtailed or Not Curtailed.");
  const effectiveDow=weight(value?.effectiveDow,"Effective Dry Operating Weight"),effectiveDowSource=value?.effectiveDowSource;if(!["fleet","standard"].includes(String(effectiveDowSource)))throw new AircraftC5Invalid("A fleet DOW or Standard Fleet Weight is required.");
  const inputMode=value?.inputMode;if(!["INDEX","MAC"].includes(String(inputMode)))throw new AircraftC5Invalid("Select Record Index or Record %MAC.");
  const raw=input as AircraftC5Values,modes={tow:envelopeMode(raw,"tow"),law:envelopeMode(raw,"law"),zfw:envelopeMode(raw,"zfw")},emptyBoundary=():EnvelopeBoundary=>({fwd:[],aft:[]});
  const result:AircraftC5Values={curtailed:curtailed as boolean|null,inputMode:inputMode as AircraftC5InputMode,effectiveDow,effectiveDowSource:effectiveDowSource as "fleet"|"standard",maximumWeights:{mrw:weight(max?.mrw,"Maximum Ramp/Taxi Weight"),tow:weight(max?.tow,"Maximum Take-Off Weight"),law:weight(max?.law,"Maximum Landing Weight"),zfw:weight(max?.zfw,"Maximum Zero Fuel Weight")},envelopes:{tow:emptyBoundary(),law:emptyBoundary(),zfw:emptyBoundary()},envelopeModes:modes,conditionalEnvelopes:{...emptyConditionalEnvelopes(),...raw.conditionalEnvelopes}};
  for(const key of ["tow","law","zfw"] as const){const maximum=result.maximumWeights[key];if(modes[key]==="CONDITIONAL"){result.conditionalEnvelopes![key]=completeConditionalEnvelopes(result.conditionalEnvelopes![key],key,maximum);continue}const source=sets?.[key] as Record<string,unknown>,boundary={fwd:points(source?.fwd,`${key.toUpperCase()} FWD`),aft:points(source?.aft,`${key.toUpperCase()} AFT`)};result.envelopes[key]=boundary;const highest=Math.max(...boundary.fwd.map(row=>row.weight),...boundary.aft.map(row=>row.weight)),fwdCoverage=Math.max(...boundary.fwd.map(row=>row.weight)),aftCoverage=Math.max(...boundary.aft.map(row=>row.weight));if(highest>maximum)throw new AircraftC5Invalid(`A ${key.toUpperCase()} envelope Weight exceeds its applicable maximum.`);if(maximum>fwdCoverage||maximum>aftCoverage)throw new AircraftC5Invalid(`The ${key.toUpperCase()} envelope must cover its applicable maximum Weight.`)}
  validateWeightHierarchy(result.maximumWeights,result.effectiveDow);return result;
}

function validateWeightHierarchy(max:{mrw:number;tow:number;law:number;zfw:number},effectiveDow=0){if(effectiveDow>0&&max.zfw>0&&effectiveDow>max.zfw)throw new AircraftC5Invalid("DOW cannot be greater than MZFW.");if(max.mrw>0&&max.tow>0&&max.tow>max.mrw)throw new AircraftC5Invalid("MTOW cannot be greater than MRW.");if(max.tow>0&&max.law>0&&max.law>max.tow)throw new AircraftC5Invalid("MLAW cannot be greater than MTOW.");if(max.law>0&&max.zfw>0&&max.zfw>max.law)throw new AircraftC5Invalid("MZFW cannot be greater than MLAW.")}
