import{aggregateConfigurationStatuses,type ConfigurationStatus}from"@/domain/configuration-status";
import{categories,pieceFields,type BaggageRecord,type BaggageSnapshot}from"@/domain/baggage-weights";

type B4SectionStatus=ConfigurationStatus|"skipped";
const whole=(value:string,positive=false)=>/^\d+$/.test(value)&&Number.isSafeInteger(Number(value))&&(positive?Number(value)>0:Number(value)>=0);
const decimal=(value:string,required=true)=>!value&&!required||/^\d+(\.\d{1,4})?$/.test(value)&&Number(value)>=0&&Number(value)<=99999999.9999;

function validDefault(row:BaggageRecord|null):boolean{
 if(!row||!["STANDARD","ACTUAL"].includes(row.values.method))return false;
 return pieceFields.every(key=>!(["male","female","child"].includes(key))&&!row.values[key]||whole(row.values[key],!["all","summer","winter"].includes(key)));
}
function validWeight(row:BaggageRecord,snapshot:BaggageSnapshot):boolean{
 const v=row.values;
 if(v.classCode&&!snapshot.classes.some(item=>item.code===v.classCode))return false;
 if(v.variation&&!snapshot.variations.some(item=>item.code===v.variation))return false;
 if(!categories.includes(v.category)||!["INHERIT","STANDARD","ACTUAL"].includes(v.pieceMethod)||!["STANDARD","ACTUAL"].includes(v.passengerMethod))return false;
 if(!v.classCode&&!v.variation&&(v.pieceMethod!=="INHERIT"||!!v.piece))return false;
 return(v.pieceMethod!=="STANDARD"||whole(v.piece))&&(v.passengerMethod!=="STANDARD"||whole(v.passenger));
}
function validPlanning(row:BaggageRecord,snapshot:BaggageSnapshot):boolean{
 const v=row.values;
 return(!v.classCode||snapshot.classes.some(item=>item.code===v.classCode))&&(!v.variation||snapshot.variations.some(item=>item.code===v.variation))&&decimal(v.bags)&&decimal(v.weight)&&decimal(v.volume,false)&&(!!v.volume||Number(snapshot.checkedBaggageDensity)>0);
}
function unique(rows:BaggageRecord[],planning=false):boolean{
 const keys=rows.map(row=>`${row.values.classCode}:${row.values.variation}:${planning?"":row.values.category}`);
 return new Set(keys).size===keys.length;
}

export function b4DefaultStatus(snapshot:BaggageSnapshot):B4SectionStatus{
 if(snapshot.operationMode==="ACTUAL")return"skipped";
 if(!snapshot.unit||!snapshot.defaults)return"incomplete";
 return validDefault(snapshot.defaults)?"configured":"partial";
}
export function b4PassengerStatus(snapshot:BaggageSnapshot):B4SectionStatus{
 if(snapshot.operationMode==="ACTUAL")return"skipped";
 const baseline=snapshot.weights.find(row=>row.baseline);
 if(!snapshot.unit||!baseline)return"incomplete";
 const resolved=snapshot.variations.every(variation=>snapshot.standardVariations.includes(variation.code)||snapshot.weights.some(row=>row.values.variation===variation.code));
 return resolved&&unique(snapshot.weights)&&snapshot.weights.every(row=>validWeight(row,snapshot))?"configured":"partial";
}
export function b4PlanningStatus(snapshot:BaggageSnapshot):ConfigurationStatus{
 if(!snapshot.unit||snapshot.planning.length===0)return"incomplete";
 return unique(snapshot.planning,true)&&snapshot.planning.every(row=>validPlanning(row,snapshot))?"configured":"partial";
}
export function b4Statuses(snapshot:BaggageSnapshot){
 const defaults=b4DefaultStatus(snapshot),passenger=b4PassengerStatus(snapshot),planning=b4PlanningStatus(snapshot);
 const required=snapshot.operationMode==="ACTUAL"?[planning]:[defaults as ConfigurationStatus,passenger as ConfigurationStatus,planning];
 const page=!snapshot.unit?"incomplete":aggregateConfigurationStatuses(required);
 return{defaults,passenger,planning,page};
}
