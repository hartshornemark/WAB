import type { AircraftC2Values } from "@/domain/aircraft-c2";
import type{AircraftC11Snapshot}from"@/domain/aircraft-c11";import type{DisplayConfigurationStatus}from"@/domain/configuration-status";
export function aircraftC11Status(s:AircraftC11Snapshot,required=true):DisplayConfigurationStatus{if(!required)return"not_required";if(!s.exists)return"incomplete";const v=s.values,a=[v.macFwdLimit,v.macAftLimit,v.stabMaxValue,v.stabMinValue,v.variationFwd,v.variationAft];return a.every(Number.isFinite)&&v.macFwdLimit<=v.variationFwd&&v.variationFwd<v.variationAft&&v.variationAft<=v.macAftLimit?"configured":"partial"}

export function aircraftC11Required(c2: Pick<AircraftC2Values,"outputs">): boolean {
 return c2.outputs.some(o => ["STABTO","STABLA"].includes(o.code.trim().toUpperCase()) && (o.selectedEdpPrelim || o.selectedAcarsPrelim || o.selectedEdpFinal || o.selectedAcarsFinal));
}
