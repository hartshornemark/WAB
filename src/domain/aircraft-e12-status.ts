import type{DisplayConfigurationStatus}from"@/domain/configuration-status";import type{AircraftE12Snapshot}from"@/domain/aircraft-e12";
const present=(v:number|null)=>typeof v==="number"&&Number.isFinite(v);
export function e12StandardStatus(s:AircraftE12Snapshot):DisplayConfigurationStatus{const n=[s.standardFleetWeight,s.standardFleetIndex].filter(present).length;return n===2?"configured":n?"partial":"incomplete"}
export function e12RegistrationsStatus(s:AircraftE12Snapshot):DisplayConfigurationStatus{if(s.registrations.some(r=>r.registration&&r.variantCode&&present(r.weight)&&present(r.index)))return"configured";return s.registrations.length?"partial":"incomplete"}
export function aircraftE12Status(s:AircraftE12Snapshot):DisplayConfigurationStatus{const a=e12StandardStatus(s),b=e12RegistrationsStatus(s);return a==="configured"&&b==="configured"?"configured":a!=="incomplete"||b!=="incomplete"?"partial":"incomplete"}
