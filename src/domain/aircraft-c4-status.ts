import type{ConfigurationStatus}from"@/domain/configuration-status";
import{validateAircraftC4,type AircraftC4Snapshot}from"@/domain/aircraft-c4";

export function aircraftC4Status(snapshot:AircraftC4Snapshot):ConfigurationStatus{
  if(!snapshot.exists)return"incomplete";
  try{validateAircraftC4(snapshot.values);return"configured";}catch{
    const values=Object.values(snapshot.values as unknown as Record<string,unknown>);
    return values.some(value=>value!==null&&value!==undefined&&value!==""&&Number.isFinite(Number(value)))?"partial":"incomplete";
  }
}
