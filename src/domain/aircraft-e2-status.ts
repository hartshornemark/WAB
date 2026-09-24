import type{DisplayConfigurationStatus}from"@/domain/configuration-status";import type{AircraftE2Snapshot,E2CrewRow,E2PantryRow}from"@/domain/aircraft-e2";
const completeCrew=(r:E2CrewRow)=>!!r.crewCode&&!!r.flightDeckLocationId&&Number.isInteger(r.flightDeckSeats)&&r.flightDeckSeats!>=0&&!!r.cabinCrewLocationId&&Number.isInteger(r.cabinCrewSeats)&&r.cabinCrewSeats!>=0;
const completePantry=(r:E2PantryRow)=>!!r.pantryCode&&!!r.galleyLocations&&Number.isInteger(r.totalWeight)&&r.totalWeight!>=0&&Number.isFinite(r.balanceArm)&&Number.isFinite(r.index);
const status=<T>(rows:T[],complete:(r:T)=>boolean):DisplayConfigurationStatus=>rows.length&&rows.every(complete)?"configured":rows.length?"partial":"incomplete";
export const e2CrewStatus=(s:AircraftE2Snapshot)=>status(s.crewRows,completeCrew);export const e2PantryStatus=(s:AircraftE2Snapshot)=>status(s.pantryRows,completePantry);
export function aircraftE2Status(s:AircraftE2Snapshot):DisplayConfigurationStatus{const a=e2CrewStatus(s),b=e2PantryStatus(s);return a==="configured"&&b==="configured"?"configured":a!=="incomplete"||b!=="incomplete"?"partial":"incomplete"}
