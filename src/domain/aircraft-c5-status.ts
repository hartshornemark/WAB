import{conditionBandsMeet,conditionalEnvelopes,envelopeMode,type AircraftC5Values,type EnvelopeBoundary,type EnvelopePoint}from"@/domain/aircraft-c5";
import type{AircraftC5Applicability}from"@/domain/aircraft-c2-status";
import{aggregateConfigurationStatuses,type ConfigurationStatus,type DisplayConfigurationStatus}from"@/domain/configuration-status";

const positiveWhole=(value:number)=>Number.isSafeInteger(value)&&value>0;
const finite=(value:number)=>Number.isFinite(value)&&Math.abs(value)<=1_000_000_000;
const pointValid=(point:EnvelopePoint,maximum:number)=>positiveWhole(point.weight)&&point.weight<=maximum&&finite(point.indexValue)&&(point.macValue===null||(finite(point.macValue)&&point.macValue>=0&&point.macValue<=100));

export function c5BoundaryStatus(points:EnvelopePoint[],maximum:number):ConfigurationStatus{
  if(points.length===0)return"incomplete";
  const configured=positiveWhole(maximum)&&points.length>=2&&new Set(points.map(point=>point.weight)).size===points.length&&points.every(point=>pointValid(point,maximum))&&points.every((point,index)=>index===0||point.weight>points[index-1].weight)&&points.some(point=>point.weight===maximum);
  return configured?"configured":"partial";
}

export function c5ConditionalEnvelopeStatus(boundary:EnvelopeBoundary,maximum:number):ConfigurationStatus{
  return aggregateConfigurationStatuses([c5BoundaryStatus(boundary.fwd,maximum),c5BoundaryStatus(boundary.aft,maximum)]);
}

export function c5StatusSelection(values:AircraftC5Values):ConfigurationStatus{return values.curtailed===null?"incomplete":"configured"}

export function c5EnvelopeStatus(values:AircraftC5Values,key:"tow"|"law"|"zfw"):ConfigurationStatus{
  const minimum=key==="zfw"?values.effectiveDow:0,maximum=values.maximumWeights[key],boundary=values.envelopes[key],variants=conditionalEnvelopes(values,key),conditional=envelopeMode(values,key)==="CONDITIONAL";
  const hasProgress=positiveWhole(maximum)||(conditional?variants.some(item=>item.boundary.fwd.length>0||item.boundary.aft.length>0):boundary.fwd.length>0||boundary.aft.length>0);
  if(!hasProgress)return"incomplete";
  if(!positiveWhole(maximum)||(positiveWhole(minimum)&&minimum>maximum)||(conditional?!conditionalComplete(variants,maximum):!boundaryComplete(boundary,maximum)))return"partial";
  if(key==="tow"&&positiveWhole(values.maximumWeights.mrw)&&maximum>values.maximumWeights.mrw)return"partial";
  if(key==="law"&&positiveWhole(values.maximumWeights.tow)&&maximum>values.maximumWeights.tow)return"partial";
  if(key==="zfw"&&positiveWhole(values.maximumWeights.law)&&maximum>values.maximumWeights.law)return"partial";
  return"configured";
}

function conditionalComplete(variants:ReturnType<typeof conditionalEnvelopes>,maximum:number){
  if(variants.length<2||new Set(variants.map(item=>item.code.trim().toUpperCase())).size!==variants.length||variants.some(item=>!item.code.trim()||!boundaryComplete(item.boundary,maximum)))return false;
  const basis=variants[0].conditionBasis;if(variants.some(item=>item.conditionBasis!==basis))return false;
  if(basis==="OTHER")return variants.every(item=>item.conditionDescription.trim().length>0);
  const ordered=[...variants].sort((a,b)=>(a.lowerBound??-1)-(b.lowerBound??-1));if(ordered[0].lowerBound!==null||ordered.at(-1)?.upperBound!==null)return false;
  return ordered.slice(1).every((current,index)=>conditionBandsMeet(ordered[index],current));
}

function boundaryComplete(boundary:EnvelopeBoundary,maximum:number){return([boundary.fwd,boundary.aft] as EnvelopePoint[][]).every(points=>c5BoundaryStatus(points,maximum)==="configured")}

const allRequired:AircraftC5Applicability={tow:true,law:true,zfw:true};
export function aircraftC5Statuses(values:AircraftC5Values,applicability:AircraftC5Applicability=allRequired){
  const status=c5StatusSelection(values);
  const tow:DisplayConfigurationStatus=applicability.tow?c5EnvelopeStatus(values,"tow"):"not_required";
  const law:DisplayConfigurationStatus=applicability.law?c5EnvelopeStatus(values,"law"):"not_required";
  const zfw:DisplayConfigurationStatus=applicability.zfw?c5EnvelopeStatus(values,"zfw"):"not_required";
  const required:ConfigurationStatus[]=[status,...(["tow","law","zfw"] as const).filter(key=>applicability[key]).map(key=>c5EnvelopeStatus(values,key))];
  return{status,tow,law,zfw,page:aggregateConfigurationStatuses(required)};
}
