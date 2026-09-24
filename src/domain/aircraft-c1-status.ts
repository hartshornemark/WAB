import type{ConfigurationStatus}from"@/domain/configuration-status";
import type{AircraftC1Snapshot}from"@/domain/aircraft-c1";

const choices={weight:["KG","LB"],length:["CM","M","IN","FT"],liquidVolume:["L","US_GAL"],volume:["M3","FT3"],fuelDensity:["KG_L","LB_L","KG_US_GAL","LB_US_GAL"],moment:["KG_IN","LB_IN","KG_CM","LB_CM","KG_M","LB_M"]}as const;
export function c1IdentityStatus(s:AircraftC1Snapshot):ConfigurationStatus{
 if(!s.exists||(!s.typeCode&&!s.subtype&&!s.identityName&&!s.aircraftName))return"incomplete";
 return /^[A-Z0-9]{3}$/.test(s.typeCode)&&/^[A-Z0-9]{1,4}$/.test(s.subtype)&&!!s.identityName.trim()&&s.identityName.length<=64&&!!s.aircraftName.trim()&&s.aircraftName.length<=64?"configured":"partial";
}
export function c1UnitsStatus(s:AircraftC1Snapshot):ConfigurationStatus{
 const entries=Object.entries(choices)as[keyof typeof choices,(typeof choices)[keyof typeof choices]][];
 const selected=entries.filter(([key])=>!!s.values[key]).length;if(selected===0)return"incomplete";
 return entries.every(([key,allowed])=>(allowed as readonly string[]).includes(s.values[key]))?"configured":"partial";
}
export function c1RemarksStatus(s:AircraftC1Snapshot):ConfigurationStatus{return s.values.remarks.length<=2000?"configured":"partial";}
export function aircraftC1Statuses(s:AircraftC1Snapshot){const identity=c1IdentityStatus(s),units=c1UnitsStatus(s),remarks=c1RemarksStatus(s);const page=identity==="incomplete"||units==="incomplete"?"incomplete":identity==="partial"||units==="partial"||remarks==="partial"?"partial":"configured";return{identity,units,remarks,page}as const;}
