import type { AircraftC2Values } from "@/domain/aircraft-c2";
import{AircraftC11Invalid,validateAircraftC11,type AircraftC11Snapshot}from"@/domain/aircraft-c11";import type{DisplayConfigurationStatus}from"@/domain/configuration-status";
export function aircraftC11Status(s:AircraftC11Snapshot,required=true):DisplayConfigurationStatus{if(!required)return"not_required";if(!s.exists)return"incomplete";try{validateAircraftC11(s.values);return"configured"}catch(error){if(error instanceof AircraftC11Invalid)return"partial";throw error}}

export function aircraftC11Required(c2: Pick<AircraftC2Values,"outputs">): boolean {
 return c2.outputs.some(o => ["STABTO","STABLA"].includes(o.code.trim().toUpperCase()) && (o.selectedEdpPrelim || o.selectedAcarsPrelim || o.selectedEdpFinal || o.selectedAcarsFinal));
}
