import type{DisplayConfigurationStatus}from"@/domain/configuration-status";import type{AircraftD4Door,AircraftD4Snapshot}from"@/domain/aircraft-d4";
export function aircraftD4DoorComplete(row:AircraftD4Door){return typeof row.forwardArm==="number"&&Number.isFinite(row.forwardArm)&&typeof row.aftArm==="number"&&Number.isFinite(row.aftArm)&&row.forwardArm<=row.aftArm&&["L","R","C"].includes(row.orientation??"")}
export function aircraftD4DoorsStatus(rows:AircraftD4Door[]):DisplayConfigurationStatus{if(rows.length===0)return"incomplete";const complete=rows.filter(aircraftD4DoorComplete).length;return complete===rows.length?"configured":complete===0?"incomplete":"partial"}
export function aircraftD4Status(snapshot:AircraftD4Snapshot){return aircraftD4DoorsStatus(snapshot.doors)}
