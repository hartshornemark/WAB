import type{DisplayConfigurationStatus}from"@/domain/configuration-status";import type{AircraftE11Snapshot}from"@/domain/aircraft-e11";
export function e11StartWeightStatus(s:AircraftE11Snapshot):DisplayConfigurationStatus{return s.principle?"configured":"incomplete"}
export function e11InclusionsStatus(s:AircraftE11Snapshot):DisplayConfigurationStatus{if(s.principle==="BASIC_WEIGHT")return"skipped";const selected=s.inclusions.filter(x=>x.included).length;if(s.principle!=="DRY_OPERATING_WEIGHT")return"incomplete";return selected>=2?"configured":selected?"partial":"incomplete"}
export function aircraftE11Status(s:AircraftE11Snapshot):DisplayConfigurationStatus{if(!s.principle)return"incomplete";if(s.principle==="BASIC_WEIGHT")return"configured";return e11InclusionsStatus(s)}
