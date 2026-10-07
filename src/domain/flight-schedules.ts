export class FlightScheduleInvalid extends Error{}
export class FlightScheduleDenied extends Error{}
export class FlightScheduleConflict extends Error{}
export function firstAircraftConfiguration(rows:Array<{typeCode:string;subtype:string;code:string}>,typeCode:string,subtype:string){return rows.find(item=>item.typeCode===typeCode&&item.subtype===subtype)?.code??null}
export function scheduleAircraftSubtype(leg:{aircraftSubtype:string|null;parameters:{aircraftSubtype:string}|null},fallback:string=""){return leg.parameters?.aircraftSubtype??leg.aircraftSubtype??fallback}
export function scheduleAircraftCarriesPassengers(rows:Array<{typeCode:string;subtype:string;operatingRole:"PASSENGER"|"FREIGHTER"|"COMBI"}>,typeCode:string|null,subtype:string|null){return rows.find(item=>item.typeCode===typeCode&&item.subtype===subtype)?.operatingRole!=="FREIGHTER"}
