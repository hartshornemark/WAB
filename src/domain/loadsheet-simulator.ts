import {macPercentForIndex} from "@/domain/aircraft-balance-formula";
import type {AircraftC4Values} from "@/domain/aircraft-c4";
import type {AircraftC11Values} from "@/domain/aircraft-c11";
import type {AircraftC5Phase,AircraftC5Values,ConditionalEnvelope,EnvelopeBoundary} from "@/domain/aircraft-c5";

export type SimulatorPassengerWeights={male:number;female:number;child:number;infant:number};
export type SimulatorPassengerLoad={areaId:string;male:number;female:number;child:number;infant:number;indexPerWeightUnit:number;maximumSeats?:number|null};
export type SimulatorDeadloadKind="BAGGAGE"|"CARGO"|"MAIL";
export type SimulatorDeadload={kind:SimulatorDeadloadKind;locationId:string;weight:number;indexPerWeightUnit:number;maximumWeight:number|null;occupiedBayIds?:string[]};
export type SimulatorFuelPoint={weight:number;index:number};
export type SimulatorDeviation={code:string;weight:number;index:number};
export type SimulatorRegistration={registration:string;dow:number;doi:number;fuelConfigurationCode:string|null};
export type SimulatorInput={
 registration:SimulatorRegistration;
 crew:SimulatorDeviation;
 pantry:SimulatorDeviation;
 passengerWeights:SimulatorPassengerWeights;
 passengers:SimulatorPassengerLoad[];
 deadload:SimulatorDeadload[];
 blockFuel:number;
 taxiFuel:number;
 tripFuel:number;
 fuelCurve:SimulatorFuelPoint[];
 formula:AircraftC4Values;
 limits:AircraftC5Values;
 stabiliser:AircraftC11Values|null;
 selectedConditionCodes?:Partial<Record<AircraftC5Phase,string>>;
};
export type SimulatorContribution={label:string;weight:number;index:number};
export type SimulatorEnvelopeResult={phase:AircraftC5Phase;code:string|null;resolved:boolean;within:boolean|null;forwardIndex:number|null;aftIndex:number|null;reason:string|null};
export type SimulatorResult={
 dow:number;doi:number;passengerWeight:number;passengerIndex:number;deadloadWeight:number;deadloadIndex:number;payload:number;
 zfw:number;lizfw:number;macZfw:number;tow:number;litow:number;macTow:number;law:number;lilaw:number;macLaw:number;
 blockFuel:number;takeoffFuel:number;landingFuel:number;tripFuel:number;takeoffFuelIndex:number;landingFuelIndex:number;
 stabTo:number|null;contributions:SimulatorContribution[];envelopes:Record<AircraftC5Phase,SimulatorEnvelopeResult>;
 structural:{zfw:boolean;tow:boolean;law:boolean};warnings:string[];
};
export class LoadsheetSimulatorInvalid extends Error{}

const finite=(value:number,label:string)=>{if(!Number.isFinite(value))throw new LoadsheetSimulatorInvalid(`Enter a valid ${label}.`);return value};
const nonNegative=(value:number,label:string)=>{finite(value,label);if(value<0)throw new LoadsheetSimulatorInvalid(`${label} cannot be negative.`);return value};
const count=(value:number,label:string)=>{nonNegative(value,label);if(!Number.isSafeInteger(value))throw new LoadsheetSimulatorInvalid(`${label} must be a whole number.`);return value};
const round=(value:number,places=6)=>Math.round(value*10**places)/10**places;

export function fuelCurveWithImplicitOrigin(points:SimulatorFuelPoint[]){
 const rows=[...points].filter(row=>Number.isFinite(row.weight)&&Number.isFinite(row.index)&&row.weight>0).sort((a,b)=>a.weight-b.weight);
 return[{weight:0,index:0},...rows];
}

export function interpolateFuelIndex(points:SimulatorFuelPoint[],weight:number){
 nonNegative(weight,"fuel weight");
 const rows=fuelCurveWithImplicitOrigin(points);
 if(rows.length<2)throw new LoadsheetSimulatorInvalid("A saved fuel loading curve is required.");
 if(weight<rows[0].weight||weight>(rows.at(-1)?.weight??0))throw new LoadsheetSimulatorInvalid(`Fuel weight ${weight} is outside the saved fuel loading curve.`);
 const exact=rows.find(row=>row.weight===weight);if(exact)return exact.index;
 const upperIndex=rows.findIndex(row=>row.weight>weight),lower=rows[upperIndex-1],upper=rows[upperIndex];
 return round(lower.index+(upper.index-lower.index)*(weight-lower.weight)/(upper.weight-lower.weight));
}

function interpolateBoundary(boundary:EnvelopeBoundary,weight:number){
 const at=(points:EnvelopeBoundary["fwd"])=>{
  const rows=[...points].sort((a,b)=>a.weight-b.weight);if(rows.length<2||weight<rows[0].weight||weight>(rows.at(-1)?.weight??0))return null;
  const exact=rows.find(row=>row.weight===weight);if(exact)return exact.indexValue;
  const upperIndex=rows.findIndex(row=>row.weight>weight),lower=rows[upperIndex-1],upper=rows[upperIndex];
  return round(lower.indexValue+(upper.indexValue-lower.indexValue)*(weight-lower.weight)/(upper.weight-lower.weight));
 };
 return{fwd:at(boundary.fwd),aft:at(boundary.aft)};
}

function conditionMatches(condition:ConditionalEnvelope,value:number){
 const lower=condition.lowerBound===null||value>condition.lowerBound||(condition.lowerInclusive&&value===condition.lowerBound);
 const upper=condition.upperBound===null||value<condition.upperBound||(condition.upperInclusive&&value===condition.upperBound);
 return lower&&upper;
}

function envelopeFor(input:SimulatorInput,phase:AircraftC5Phase,weight:number,index:number,takeoffFuel:number,landingFuel:number):SimulatorEnvelopeResult{
 const mode=input.limits.envelopeModes?.[phase]??"STANDARD";let boundary=input.limits.envelopes[phase],code:string|null=null;
 if(mode==="CONDITIONAL"){
  const candidates=(input.limits.conditionalEnvelopes?.[phase]??[]).filter(condition=>!condition.configurationCode||condition.configurationCode===input.registration.fuelConfigurationCode);
  const explicit=input.selectedConditionCodes?.[phase],selected=explicit?candidates.find(condition=>condition.code===explicit):candidates.find(condition=>condition.conditionBasis!=="OTHER"&&conditionMatches(condition,condition.conditionBasis==="LANDING_FUEL"?landingFuel:takeoffFuel));
  if(!selected)return{phase,code:null,resolved:false,within:null,forwardIndex:null,aftIndex:null,reason:explicit?`Conditional envelope ${explicit} is not available.`:"No applicable conditional envelope could be selected."};
  boundary=selected.boundary;code=selected.code;
 }
 const limits=interpolateBoundary(boundary,weight);
 if(limits.fwd===null||limits.aft===null)return{phase,code,resolved:true,within:false,forwardIndex:limits.fwd,aftIndex:limits.aft,reason:"Weight is outside the saved envelope range."};
 const low=Math.min(limits.fwd,limits.aft),high=Math.max(limits.fwd,limits.aft),within=index>=low&&index<=high;
 return{phase,code,resolved:true,within,forwardIndex:limits.fwd,aftIndex:limits.aft,reason:within?null:`Loaded index ${round(index,3)} is outside ${round(low,3)} to ${round(high,3)}.`};
}

function linearStabiliser(values:AircraftC11Values,mac:number){
 if(mac<=values.variationFwd)return values.stabMaxValue;
 if(mac>=values.variationAft)return values.stabMinValue;
 return round(values.stabMaxValue+(values.stabMinValue-values.stabMaxValue)*(mac-values.variationFwd)/(values.variationAft-values.variationFwd),3);
}
function matrixAtRow(values:AircraftC11Values,rowIndex:number,mac:number){
 const row=values.rows[rowIndex],points=values.macColumns.map((column,index)=>({mac:column,trim:row.trimValues[index]})).filter((point):point is{mac:number;trim:number}=>point.trim!==null);
 if(points.length<2||mac<points[0].mac||mac>(points.at(-1)?.mac??0))return null;
 const exact=points.find(point=>point.mac===mac);if(exact)return exact.trim;
 const upperIndex=points.findIndex(point=>point.mac>mac),lower=points[upperIndex-1],upper=points[upperIndex];
 return lower.trim+(upper.trim-lower.trim)*(mac-lower.mac)/(upper.mac-lower.mac);
}
export function stabiliserAt(values:AircraftC11Values|null,tow:number,mac:number){
 if(!values)return null;if(values.method==="LINEAR")return linearStabiliser(values,mac);
 const available=values.rows.map((row,index)=>({tow:row.tow,trim:matrixAtRow(values,index,mac)})).filter((row):row is{tow:number;trim:number}=>row.trim!==null);
 if(!available.length||tow<available[0].tow||tow>(available.at(-1)?.tow??0))return null;
 const exact=available.find(row=>row.tow===tow);if(exact)return round(exact.trim,3);
 const upperIndex=available.findIndex(row=>row.tow>tow),lower=available[upperIndex-1],upper=available[upperIndex];
 return round(lower.trim+(upper.trim-lower.trim)*(tow-lower.tow)/(upper.tow-lower.tow),3);
}

export function simulateLoadsheet(input:SimulatorInput):SimulatorResult{
 const warnings:string[]=[];nonNegative(input.registration.dow,"registration DOW");finite(input.registration.doi,"registration DOI");
 const dow=round(input.registration.dow+finite(input.crew.weight,"crew weight adjustment")+finite(input.pantry.weight,"pantry weight adjustment"));
 const doi=round(input.registration.doi+finite(input.crew.index,"crew index adjustment")+finite(input.pantry.index,"pantry index adjustment"));
 for(const[key,value]of Object.entries(input.passengerWeights))nonNegative(value,`${key} passenger weight`);
 let passengerWeight=0,passengerIndex=0;
 for(const area of input.passengers){const male=count(area.male,`${area.areaId} male passengers`),female=count(area.female,`${area.areaId} female passengers`),child=count(area.child,`${area.areaId} child passengers`),infant=count(area.infant,`${area.areaId} infants`),seated=male+female+child;if(area.maximumSeats!==null&&area.maximumSeats!==undefined&&seated>area.maximumSeats)warnings.push(`${area.areaId} exceeds its configured seating capacity by ${seated-area.maximumSeats} passenger${seated-area.maximumSeats===1?"":"s"}.`);const areaWeight=male*input.passengerWeights.male+female*input.passengerWeights.female+child*input.passengerWeights.child+infant*input.passengerWeights.infant;passengerWeight+=areaWeight;passengerIndex+=areaWeight*finite(area.indexPerWeightUnit,`${area.areaId} Index per Weight Unit`)}
 let deadloadWeight=0,deadloadIndex=0;const occupiedBays=new Set<string>();for(const load of input.deadload){nonNegative(load.weight,`${load.locationId} load weight`);if(load.maximumWeight!==null&&load.weight>load.maximumWeight)warnings.push(`${load.locationId} exceeds its maximum weight by ${round(load.weight-load.maximumWeight)}.`);for(const bay of load.occupiedBayIds??[]){if(occupiedBays.has(bay))warnings.push(`${load.locationId} overlaps another selected ULD position at bay ${bay}.`);occupiedBays.add(bay)}deadloadWeight+=load.weight;deadloadIndex+=load.weight*finite(load.indexPerWeightUnit,`${load.locationId} Index per Weight Unit`)}
 passengerWeight=round(passengerWeight);passengerIndex=round(passengerIndex);deadloadWeight=round(deadloadWeight);deadloadIndex=round(deadloadIndex);
 const payload=round(passengerWeight+deadloadWeight),zfw=round(dow+payload),lizfw=round(doi+passengerIndex+deadloadIndex),blockFuel=nonNegative(input.blockFuel,"block fuel"),taxiFuel=nonNegative(input.taxiFuel,"taxi fuel"),tripFuel=nonNegative(input.tripFuel,"trip fuel");
 if(taxiFuel>blockFuel)throw new LoadsheetSimulatorInvalid("Taxi fuel cannot exceed block fuel.");const takeoffFuel=round(blockFuel-taxiFuel);if(tripFuel>takeoffFuel)throw new LoadsheetSimulatorInvalid("Trip fuel cannot exceed take-off fuel.");const landingFuel=round(takeoffFuel-tripFuel);
 const takeoffFuelIndex=interpolateFuelIndex(input.fuelCurve,takeoffFuel),landingFuelIndex=interpolateFuelIndex(input.fuelCurve,landingFuel),tow=round(zfw+takeoffFuel),litow=round(lizfw+takeoffFuelIndex),law=round(zfw+landingFuel),lilaw=round(lizfw+landingFuelIndex);
 const macZfw=round(macPercentForIndex(zfw,lizfw,input.formula),3),macTow=round(macPercentForIndex(tow,litow,input.formula),3),macLaw=round(macPercentForIndex(law,lilaw,input.formula),3),stabTo=stabiliserAt(input.stabiliser,tow,macTow);
 const structural={zfw:zfw<=input.limits.maximumWeights.zfw,tow:tow<=input.limits.maximumWeights.tow,law:law<=input.limits.maximumWeights.law};
 if(!structural.zfw)warnings.push(`ZFW exceeds MZFW by ${round(zfw-input.limits.maximumWeights.zfw)}.`);if(!structural.tow)warnings.push(`TOW exceeds MTOW by ${round(tow-input.limits.maximumWeights.tow)}.`);if(!structural.law)warnings.push(`LAW exceeds MLAW by ${round(law-input.limits.maximumWeights.law)}.`);if(input.stabiliser&&stabTo===null)warnings.push("STABTO is outside the saved stabiliser table.");
 const envelopes={zfw:envelopeFor(input,"zfw",zfw,lizfw,takeoffFuel,landingFuel),tow:envelopeFor(input,"tow",tow,litow,takeoffFuel,landingFuel),law:envelopeFor(input,"law",law,lilaw,takeoffFuel,landingFuel)};
 for(const result of Object.values(envelopes))if(result.within===false||!result.resolved)warnings.push(`${result.phase.toUpperCase()}: ${result.reason}`);
 const contributions=[{label:`Registration ${input.registration.registration}`,weight:input.registration.dow,index:input.registration.doi},{label:`Crew Code ${input.crew.code}`,weight:input.crew.weight,index:input.crew.index},{label:`Pantry Code ${input.pantry.code}`,weight:input.pantry.weight,index:input.pantry.index},{label:"Passengers",weight:passengerWeight,index:passengerIndex},{label:"Deadload",weight:deadloadWeight,index:deadloadIndex},{label:"Take-off Fuel (ZFW → TOW)",weight:takeoffFuel,index:takeoffFuelIndex},{label:"Landing Fuel (ZFW → LAW)",weight:landingFuel,index:landingFuelIndex}];
 return{dow,doi,passengerWeight,passengerIndex,deadloadWeight,deadloadIndex,payload,zfw,lizfw,macZfw,tow,litow,macTow,law,lilaw,macLaw,blockFuel,takeoffFuel,landingFuel,tripFuel,takeoffFuelIndex,landingFuelIndex,stabTo,contributions,envelopes,structural,warnings};
}
