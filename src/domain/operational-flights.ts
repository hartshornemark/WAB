export class OperationalFlightInvalid extends Error{}
export class OperationalFlightDenied extends Error{}
export class OperationalFlightConflict extends Error{}

export const operationalFlightStatuses=["SCHEDULED","INITIATED","LOAD_PLANNING","LOADSHEET_PRELIMINARY","LOADSHEET_FINAL","CLOSED","CANCELLED"] as const;
export type OperationalFlightStatus=(typeof operationalFlightStatuses)[number];

export function validServiceDate(value:unknown){const date=String(value??"").trim();if(!/^\d{4}-\d{2}-\d{2}$/.test(date)||Number.isNaN(Date.parse(`${date}T00:00:00Z`)))throw new OperationalFlightInvalid("Select a valid operating date.");return date}
export function validUuid(value:unknown){const id=String(value??"").trim();if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id))throw new OperationalFlightInvalid("The selected flight is invalid.");return id}
export function operationalFlightLabel(status:OperationalFlightStatus){return status.split("_").map(word=>word[0]+word.slice(1).toLowerCase()).join(" ")}
export function operationalWeightBasis(operatingRole:string|undefined,basis:string|null){return operatingRole==="FREIGHTER"?null:basis}
export function departureStationCodes(flights:Array<{departureAirport:string}>){return new Set(flights.map(flight=>flight.departureAirport.trim().toUpperCase()).filter(code=>/^[A-Z]{3}$/.test(code)))}
