import {aggregateConfigurationStatuses,type ConfigurationStatus} from "@/domain/configuration-status";
import {passengerFields,type FlightVariation,type PassengerRow,type PassengerSnapshot,type PassengerValues} from "@/domain/passenger-weights";

function validWeights(values:PassengerValues):boolean{
  if(typeof values.includesHandBaggage!=="boolean"||typeof values.remarks!=="string"||values.remarks.length>2000)return false;
  return passengerFields.every(key=>{
    const value=values[key];
    if(value===null)return key==="adult"||(key==="handBaggage"&&values.includesHandBaggage);
    if(!Number.isSafeInteger(value))return false;
    return key==="infant"||key==="handBaggage"?value>=0:value>0;
  });
}

function validVariations(rows:FlightVariation[]):boolean{
  const codes=new Set<string>(),descriptions=new Set<string>();
  return rows.length<=100&&rows.every(row=>{
    const code=row.code.trim().toUpperCase(),description=row.description.trim(),label=description.toLowerCase();
    if(!/^[A-Z0-9]{3}$/.test(code)||!description||description.length>64||codes.has(code)||descriptions.has(label))return false;
    codes.add(code);descriptions.add(label);return true;
  });
}

function validClassRows(rows:PassengerRow[],classes:FlightVariation[],variations:FlightVariation[]):boolean{
  const classCodes=new Set(classes.map(row=>row.code)),variationCodes=new Set(variations.map(row=>row.code)),pairs=new Set<string>();
  return rows.length<=200&&rows.every(row=>{
    const pair=`${row.classCode}:${row.variation??""}`;
    if((row.classCode!==null&&!classCodes.has(row.classCode))||(row.variation!==null&&!variationCodes.has(row.variation))||(row.classCode===null&&row.variation===null)||pairs.has(pair)||!validWeights(row))return false;
    pairs.add(pair);return true;
  });
}

export function b3DefaultStatus(snapshot:PassengerSnapshot):ConfigurationStatus{
  if(!snapshot.unit||!snapshot.defaultWeights)return "incomplete";
  return validWeights(snapshot.defaultWeights)?"configured":"partial";
}

export function b3VariationsStatus(snapshot:PassengerSnapshot):ConfigurationStatus{
  if(snapshot.variations.length===0)return snapshot.variationsReviewed?"configured":"incomplete";
  return validVariations(snapshot.variations)?"configured":"partial";
}

export function b3ClassWeightsStatus(snapshot:PassengerSnapshot):ConfigurationStatus{
  if(snapshot.rows.length===0)return snapshot.classWeightsReviewed?"configured":"incomplete";
  return validClassRows(snapshot.rows,snapshot.classes,snapshot.variations)?"configured":"partial";
}

export function b3Statuses(snapshot:PassengerSnapshot){
  const standard=b3DefaultStatus(snapshot),variations=b3VariationsStatus(snapshot),classWeights=b3ClassWeightsStatus(snapshot);
  const applicable:ConfigurationStatus[]=[standard,variations,classWeights];
  const page=standard==="incomplete"?"incomplete":standard==="partial"?"partial":aggregateConfigurationStatuses(applicable);
  return{standard,variations,classWeights,page};
}
