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
export type FreightPlanningInput={weightBasis:"FLEET_WEIGHT"|"REGISTRATION";registration:string|null;crewCode:string;pantryCode:string};
export function validFreightPlanning(value:unknown):FreightPlanningInput{const row=value as Partial<FreightPlanningInput>,weightBasis=row?.weightBasis,registration=String(row?.registration??"").trim().toUpperCase()||null,crewCode=String(row?.crewCode??"").trim().toUpperCase(),pantryCode=String(row?.pantryCode??"").trim().toUpperCase();if(weightBasis!=="FLEET_WEIGHT"&&weightBasis!=="REGISTRATION")throw new OperationalFlightInvalid("Select Fleet Weight or an aircraft registration.");if(weightBasis==="REGISTRATION"&&!registration)throw new OperationalFlightInvalid("Select an aircraft registration.");if(weightBasis==="FLEET_WEIGHT"&&registration)throw new OperationalFlightInvalid("Fleet Weight cannot include a registration.");if(registration&&!/^[A-Z0-9][A-Z0-9-]{0,9}$/.test(registration))throw new OperationalFlightInvalid("Select a valid aircraft registration.");if(!/^[A-Z0-9]$/.test(crewCode))throw new OperationalFlightInvalid("Select a valid crew code.");if(!/^[A-Z0-9]$/.test(pantryCode))throw new OperationalFlightInvalid("Select a valid pantry code.");return{weightBasis,registration,crewCode,pantryCode}}
