import {aggregateConfigurationStatuses,type ConfigurationStatus} from "@/domain/configuration-status";
import type {CrewSnapshot,CrewWeightKey} from "@/domain/crew-weights";

const crewKeys = ["flightDeckMale","flightDeckFemale","cabinMale","cabinFemale"] as const satisfies readonly CrewWeightKey[];

function positiveWhole(value:number|null):boolean{
  return typeof value==="number"&&Number.isSafeInteger(value)&&value>0;
}

function nonnegativeWhole(value:number|null):boolean{
  return typeof value==="number"&&Number.isSafeInteger(value)&&value>=0;
}

export function b2CrewWeightsStatus(snapshot:CrewSnapshot):ConfigurationStatus{
  if(!snapshot.unit||!snapshot.exists)return "incomplete";
  return crewKeys.every(key=>positiveWhole(snapshot.values[key]))?"configured":"partial";
}

export function b2HandBaggageStatus(snapshot:CrewSnapshot):ConfigurationStatus{
  if(!snapshot.exists)return "incomplete";
  if(snapshot.values.includesHandBaggage)return "configured";
  return nonnegativeWhole(snapshot.values.flightDeckHand)&&nonnegativeWhole(snapshot.values.cabinHand)?"configured":"partial";
}

export function b2HoldBaggageStatus(snapshot:CrewSnapshot):ConfigurationStatus{
  const {allFlights,longhaul,shorthaul}=snapshot.values;
  if(!allFlights&&!longhaul&&!shorthaul)return "incomplete";
  if(allFlights&&(longhaul||shorthaul))return "partial";
  const selected=[
    allFlights&&nonnegativeWhole(snapshot.values.flightDeckOther)&&nonnegativeWhole(snapshot.values.cabinOther),
    longhaul&&nonnegativeWhole(snapshot.values.flightDeckLong)&&nonnegativeWhole(snapshot.values.cabinLong),
    shorthaul&&nonnegativeWhole(snapshot.values.flightDeckShort)&&nonnegativeWhole(snapshot.values.cabinShort),
  ];
  const valid=(!allFlights||selected[0])&&(!longhaul||selected[1])&&(!shorthaul||selected[2]);
  return valid?"configured":"partial";
}

export function b2Statuses(snapshot:CrewSnapshot){
  const crewWeights=b2CrewWeightsStatus(snapshot);
  const handBaggage=b2HandBaggageStatus(snapshot);
  const holdBaggage=b2HoldBaggageStatus(snapshot);
  return{
    crewWeights,
    handBaggage,
    holdBaggage,
    page:snapshot.unit?aggregateConfigurationStatuses([crewWeights,handBaggage,holdBaggage]):"incomplete" as ConfigurationStatus,
  };
}
