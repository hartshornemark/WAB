import type{AircraftC5Values,EnvelopeBoundary,EnvelopePoint}from"@/domain/aircraft-c5";
import type{AircraftC5Applicability}from"@/domain/aircraft-c2-status";
import{aggregateConfigurationStatuses,type ConfigurationStatus,type DisplayConfigurationStatus}from"@/domain/configuration-status";

const positiveWhole=(value:number)=>Number.isSafeInteger(value)&&value>0;
const finite=(value:number)=>Number.isFinite(value)&&Math.abs(value)<=1_000_000_000;
const pointValid=(point:EnvelopePoint,maximum:number)=>positiveWhole(point.weight)&&point.weight<=maximum&&finite(point.indexValue)&&(point.macValue===null||(finite(point.macValue)&&point.macValue>=0&&point.macValue<=100));

export function c5StatusSelection(values:AircraftC5Values):ConfigurationStatus{return values.curtailed===null?"incomplete":"configured"}

export function c5EnvelopeStatus(values:AircraftC5Values,key:"tow"|"law"|"zfw"):ConfigurationStatus{
  const minimum=values.effectiveDow,maximum=values.maximumWeights[key],boundary=values.envelopes[key];
  const hasProgress=positiveWhole(maximum)||boundary.fwd.length>0||boundary.aft.length>0;
  if(!hasProgress)return"incomplete";
  if(!positiveWhole(maximum)||(positiveWhole(minimum)&&minimum>maximum)||!boundaryComplete(boundary,minimum,maximum))return"partial";
  if(key==="tow"&&positiveWhole(values.maximumWeights.mrw)&&maximum>values.maximumWeights.mrw)return"partial";
  if(key==="law"&&positiveWhole(values.maximumWeights.tow)&&maximum>values.maximumWeights.tow)return"partial";
  if(key==="zfw"&&positiveWhole(values.maximumWeights.law)&&maximum>values.maximumWeights.law)return"partial";
  return"configured";
}

function boundaryComplete(boundary:EnvelopeBoundary,minimum:number,maximum:number){return([boundary.fwd,boundary.aft] as EnvelopePoint[][]).every(points=>points.length>=2&&new Set(points.map(point=>point.weight)).size===points.length&&points.every(point=>pointValid(point,maximum))&&points.every((point,index)=>index===0||point.weight>points[index-1].weight)&&(!positiveWhole(minimum)||points[0].weight<=minimum)&&points.at(-1)?.weight===maximum)}

const allRequired:AircraftC5Applicability={tow:true,law:true,zfw:true};
export function aircraftC5Statuses(values:AircraftC5Values,applicability:AircraftC5Applicability=allRequired){
  const status=c5StatusSelection(values);
  const tow:DisplayConfigurationStatus=applicability.tow?c5EnvelopeStatus(values,"tow"):"not_required";
  const law:DisplayConfigurationStatus=applicability.law?c5EnvelopeStatus(values,"law"):"not_required";
  const zfw:DisplayConfigurationStatus=applicability.zfw?c5EnvelopeStatus(values,"zfw"):"not_required";
  const required:ConfigurationStatus[]=[status,...(["tow","law","zfw"] as const).filter(key=>applicability[key]).map(key=>c5EnvelopeStatus(values,key))];
  return{status,tow,law,zfw,page:aggregateConfigurationStatuses(required)};
}
