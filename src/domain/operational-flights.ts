export class OperationalFlightInvalid extends Error{}
export class OperationalFlightDenied extends Error{}
export class OperationalFlightConflict extends Error{}

export const operationalFlightStatuses=["SCHEDULED","INITIATED","LOAD_PLANNING","LOADSHEET_PRELIMINARY","LOADSHEET_FINAL","CLOSED","CANCELLED"] as const;
export type OperationalFlightStatus=(typeof operationalFlightStatuses)[number];

export function validServiceDate(value:unknown){const date=String(value??"").trim();if(!/^\d{4}-\d{2}-\d{2}$/.test(date)||Number.isNaN(Date.parse(`${date}T00:00:00Z`)))throw new OperationalFlightInvalid("Select a valid operating date.");return date}
export function validUuid(value:unknown){const id=String(value??"").trim();if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id))throw new OperationalFlightInvalid("The selected flight is invalid.");return id}
export function operationalFlightLabel(status:OperationalFlightStatus){return status.split("_").map(word=>word[0]+word.slice(1).toLowerCase()).join(" ")}
export type OperationalFlightTimingTone="future"|"upcoming"|"due"|"overdue"|"complete"|"cancelled"|"unknown";
export type OperationalFlightTiming={label:string;tone:OperationalFlightTimingTone};

function scheduledInstant(value:string,utcOffsetMinutes:number|null){
  const local=/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?$/.exec(value);
  if(local){
    const[,year,month,day,hour,minute,second="0"]=local;
    return Date.UTC(Number(year),Number(month)-1,Number(day),Number(hour),Number(minute),Number(second))-(utcOffsetMinutes??0)*60_000;
  }
  return Date.parse(value);
}

function compactElapsed(milliseconds:number){
  const totalMinutes=Math.max(1,Math.floor(Math.abs(milliseconds)/60_000));
  const days=Math.floor(totalMinutes/1_440),hours=Math.floor(totalMinutes%1_440/60),minutes=totalMinutes%60;
  if(days)return `${days}D ${hours}H`;
  if(hours)return `${hours}H ${minutes}M`;
  return `${minutes}M`;
}
export function operationalFlightTiming(departureLocal:string,utcOffsetMinutes:number|null,status:OperationalFlightStatus,now:Date=new Date(),delayMinutes=0):OperationalFlightTiming{
  if(status==="CANCELLED")return{label:"NOT OPERATING",tone:"cancelled"};
  const departure=scheduledInstant(departureLocal,utcOffsetMinutes)+delayMinutes*60_000;
  if(!Number.isFinite(departure))return{label:"TIME UNKNOWN",tone:"unknown"};
  const difference=departure-now.getTime();
  if(Math.abs(difference)<60_000)return{label:"STD NOW",tone:status==="LOADSHEET_FINAL"||status==="CLOSED"?"complete":"due"};
  if(difference<0)return{label:`STD + ${compactElapsed(difference)}`,tone:status==="LOADSHEET_FINAL"||status==="CLOSED"?"complete":"overdue"};
  if(difference<=2*60*60_000)return{label:`STD − ${compactElapsed(difference)}`,tone:"due"};
  if(difference<=24*60*60_000)return{label:`STD − ${compactElapsed(difference)}`,tone:"upcoming"};
  return{label:`STD − ${compactElapsed(difference)}`,tone:"future"};
}
export function operationalFlightProcessStatus(status:OperationalFlightStatus,signals:{loadPlanEdition:number;loadPlanFinal:boolean;loadsheetFinal:boolean;freightReleased:boolean}){
  if(status==="CANCELLED"||status==="CLOSED")return status;
  const rank:Record<OperationalFlightStatus,number>={SCHEDULED:0,INITIATED:1,LOAD_PLANNING:2,LOADSHEET_PRELIMINARY:3,LOADSHEET_FINAL:4,CLOSED:5,CANCELLED:6};
  let derived:OperationalFlightStatus=status;
  const advance=(candidate:OperationalFlightStatus)=>{if(rank[candidate]>rank[derived])derived=candidate};
  if(signals.freightReleased||signals.loadPlanEdition>0)advance("LOAD_PLANNING");
  if(signals.loadPlanFinal)advance("LOADSHEET_PRELIMINARY");
  if(signals.loadsheetFinal)advance("LOADSHEET_FINAL");
  return derived;
}
export function operationalWeightBasis(operatingRole:string|undefined,basis:string|null){return operatingRole==="FREIGHTER"?null:basis}
export function departureStationCodes(flights:Array<{departureAirport:string}>){return new Set(flights.map(flight=>flight.departureAirport.trim().toUpperCase()).filter(code=>/^[A-Z]{3}$/.test(code)))}
export type FreightPlanningInput={weightBasis:"FLEET_WEIGHT"|"REGISTRATION";registration:string|null;crewCode:string;pantryCode:string};
export function operationalAircraftAssignmentReady(value:{weightBasis:"FLEET_WEIGHT"|"REGISTRATION";registration:string|null;crewCode:string|null;pantryCode:string|null}){return Boolean(value.crewCode&&value.pantryCode&&(value.weightBasis==="FLEET_WEIGHT"||value.registration))}
export function validFreightPlanning(value:unknown):FreightPlanningInput{const row=value as Partial<FreightPlanningInput>,weightBasis=row?.weightBasis,registration=String(row?.registration??"").trim().toUpperCase()||null,crewCode=String(row?.crewCode??"").trim().toUpperCase(),pantryCode=String(row?.pantryCode??"").trim().toUpperCase();if(weightBasis!=="FLEET_WEIGHT"&&weightBasis!=="REGISTRATION")throw new OperationalFlightInvalid("Select Fleet Weight or an aircraft registration.");if(weightBasis==="REGISTRATION"&&!registration)throw new OperationalFlightInvalid("Select an aircraft registration.");if(weightBasis==="FLEET_WEIGHT"&&registration)throw new OperationalFlightInvalid("Fleet Weight cannot include a registration.");if(registration&&!/^[A-Z0-9][A-Z0-9-]{0,9}$/.test(registration))throw new OperationalFlightInvalid("Select a valid aircraft registration.");if(!/^[A-Z0-9]$/.test(crewCode))throw new OperationalFlightInvalid("Select a valid crew code.");if(!/^[A-Z0-9]$/.test(pantryCode))throw new OperationalFlightInvalid("Select a valid pantry code.");return{weightBasis,registration,crewCode,pantryCode}}

export type PlanningBaggageContent={loadId:string;kind:"ULD"|"BULK";uldCode:string|null;uldNumber:null;pieces:number;netWeight:number};
export type BaggageAccommodationInput={uldCount:number;uldNetWeight:number;bulkNetWeight:number;contents:PlanningBaggageContent[]};
export function validBaggageAccommodation(value:unknown):BaggageAccommodationInput{
 const row=value as Partial<BaggageAccommodationInput>,uldCount=Number(row?.uldCount),uldNetWeight=Number(row?.uldNetWeight),bulkNetWeight=Number(row?.bulkNetWeight);
 if(!Number.isSafeInteger(uldCount)||uldCount<0||!Number.isFinite(uldNetWeight)||uldNetWeight<0||!Number.isFinite(bulkNetWeight)||bulkNetWeight<0||!Array.isArray(row.contents))throw new OperationalFlightInvalid("Enter valid non-negative baggage accommodation values.");
 const seen=new Set<string>(),contents=row.contents.map(value=>{const item=value as Partial<PlanningBaggageContent>,kind=String(item.kind??"").toUpperCase(),loadId=String(item.loadId??"").trim(),uldCode=String(item.uldCode??"").trim().toUpperCase()||null,pieces=Number(item.pieces),netWeight=Number(item.netWeight);if(!(["ULD","BULK"] as string[]).includes(kind)||!loadId||seen.has(loadId)||!Number.isSafeInteger(pieces)||pieces<0||pieces>9999||!Number.isFinite(netWeight)||netWeight<0||netWeight>100000)throw new OperationalFlightInvalid("Check each planned baggage-content row.");if(kind==="ULD"&&!/^PLANNED_BAGGAGE:\d+$/.test(loadId))throw new OperationalFlightInvalid("Check each planned baggage ULD.");if(kind==="BULK"&&loadId!=="PLANNED_BAGGAGE:BULK")throw new OperationalFlightInvalid("Only one planned Bulk baggage load may be recorded.");seen.add(loadId);return{loadId,kind:kind as"ULD"|"BULK",uldCode:kind==="ULD"?uldCode:null,uldNumber:null,pieces,netWeight:Math.round(netWeight)}});
 const ulds=contents.filter(item=>item.kind==="ULD"),bulk=contents.filter(item=>item.kind==="BULK");
 if(ulds.length!==uldCount||bulk.length>1)throw new OperationalFlightInvalid("The planned baggage contents must match the selected ULD count and may include one Bulk load.");
 if(Math.abs(ulds.reduce((sum,item)=>sum+item.netWeight,0)-uldNetWeight)>.5||Math.abs(bulk.reduce((sum,item)=>sum+item.netWeight,0)-bulkNetWeight)>.5)throw new OperationalFlightInvalid("Reconcile the planned baggage-content weights with the ULD and Bulk accommodation.");
 return{uldCount,uldNetWeight:Math.round(uldNetWeight),bulkNetWeight:Math.round(bulkNetWeight),contents};
}
