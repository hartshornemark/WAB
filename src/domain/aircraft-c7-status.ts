import type{AircraftC7Point,AircraftC7Section,AircraftC7Values}from"@/domain/aircraft-c7";
import type{ConfigurationStatus,DisplayConfigurationStatus}from"@/domain/configuration-status";

const finite=(value:number|null)=>value!==null&&Number.isFinite(value)&&Math.abs(value)<=1_000_000_000;
const validPoint=(point:AircraftC7Point,maximumRampWeight:number|null)=>Number.isSafeInteger(point.weight)&&point.weight>0&&(!maximumRampWeight||point.weight<=maximumRampWeight)&&(finite(point.indexValue)||(finite(point.macValue)&&point.macValue!<0&&point.macValue!<=100))&&(point.macValue===null||(finite(point.macValue)&&point.macValue>=0&&point.macValue<=100));
const validSet=(section:AircraftC7Section,maximumRampWeight:number|null)=>new Set(section.points.map(point=>point.weight)).size===section.points.length&&section.points.every((point,index)=>validPoint(point,maximumRampWeight)&&(index===0||point.weight>section.points[index-1].weight));

export function idealTrimStatus(section:AircraftC7Section,maximumRampWeight:number|null):DisplayConfigurationStatus{
  if(!section.enabled)return"skipped";
  if(section.points.length===0)return"incomplete";
  if(section.points.length===1)return"partial";
  return validSet(section,maximumRampWeight)?"configured":"partial";
}

export function tippingLimitsStatus(section:AircraftC7Section,maximumRampWeight:number|null):DisplayConfigurationStatus{
  if(!section.enabled)return"skipped";
  if(section.points.length===0)return"incomplete";
  return validSet(section,maximumRampWeight)?"configured":"partial";
}

export function aircraftC7Statuses(values:AircraftC7Values,maximumRampWeight:number|null){
  const idealTrim=idealTrimStatus(values.idealTrim,maximumRampWeight),tippingLimits=tippingLimitsStatus(values.tippingLimits,maximumRampWeight),applicable=[idealTrim,tippingLimits].filter((status):status is ConfigurationStatus=>status!=="skipped");
  const page:DisplayConfigurationStatus=applicable.length===0?"skipped":applicable.every(status=>status==="configured")?"configured":applicable.every(status=>status==="incomplete")?"incomplete":"partial";
  return{idealTrim,tippingLimits,lateralImbalance:"unsupported" as const,page};
}
