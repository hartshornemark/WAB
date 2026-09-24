import "server-only";
import { createHash } from "node:crypto";
import { DataUnavailable } from "@/domain/models";
import { BaggageConflict,BaggageDenied,BaggageInvalid,type BaggageRecord,type BaggageSection,type BaggageVariationMethod } from "@/domain/baggage-weights";
import type { BaggageRepository } from "@/ports/baggage-repository";
import type { RequestClient } from "./server";
import { createPassengerAdapter } from "./passenger-adapter";
import { createDetailsAdapter } from "./details-adapter";
const tables={defaults:"Carrier_Baggage_Weights_ALLFLIGHTS",weights:"Carrier_Baggage_Weights_BYCLASS",planning:"Carrier_Planning_Assumptions"} as const;
const ids={defaults:"Carrier_IATA",weights:"Baggage_Weight_Set_ID",planning:"Planning_Assumption_UUID"};
const maps:Record<BaggageSection,Record<string,string>>={defaults:{male:"Bag_Adult_Male",female:"Bag_Adult_Female",child:"Bag_Adult_Child",all:"Bag_Standard_All",summer:"Bag_Standard_Summer",winter:"Bag_Standard_Winter",method:"Per_Piece_Method",remarks:"Remarks"},weights:{classCode:"Class_Code",variation:"Flight_Type_Variation",category:"Passenger_Category",pieceMethod:"Per_Piece_Method",passengerMethod:"Per_Passenger_Method",piece:"Baggage_Weight_Per_Piece",passenger:"Baggage_Weight_Per_Passenger",remarks:"Remarks"},planning:{classCode:"Class_Code",variation:"Flight_Type_Variation",bags:"Average_Bags_Per_Passenger",weight:"Average_Bag_Weight_Per_Passenger",volume:"Average_Bag_Volume",remarks:"Remarks"}};
const numeric=new Set(["male","female","child","all","summer","winter","piece","passenger","bags","weight","volume"]);
type Raw=Record<string,string|number|boolean|null>;
function record(section:BaggageSection,row:Raw):BaggageRecord{return {id:String(row[ids[section]]),baseline:row.Is_Baseline===true,values:Object.fromEntries(Object.entries(maps[section]).map(([key,col])=>[key,row[col]?.toString()??""]))};}
function fail(error:{code?:string}|null){
 if(!error)return;
 if(error.code==="42501")throw new BaggageDenied();
 if(error.code==="23505")throw new BaggageInvalid("A record already exists for these selections. Reload and edit that record.");
 if(error.code==="23503")throw new BaggageInvalid("A class, variation or default record changed. Reload and check your selections.");
 if(["23514","23502","22P02","22003"].includes(error.code??""))throw new BaggageInvalid("Check the required weights, methods and planning values.");
 throw new DataUnavailable();
}
export function createBaggageAdapter(client:RequestClient):BaggageRepository {
 const api=()=>client.schema("Basic_Carrier_Record");
 async function read(iata:string){
  const [context,details,a,b,c,reviews,density]=await Promise.all([createPassengerAdapter(client).get(iata),createDetailsAdapter(client).get(iata),api().from(tables.defaults).select("*").eq("Carrier_IATA",iata),api().from(tables.weights).select("*").eq("Carrier_IATA",iata).order("Baggage_Weight_Set_ID"),api().from(tables.planning).select("*").eq("Carrier_IATA",iata).order("Planning_Assumption_UUID"),api().from("Carrier_Configuration_Review_State").select("Section_Code,Review_State,Reviewed_At").eq("Carrier_IATA",iata).eq("Page_Code","B4"),api().from("Carrier_Units_of_Measure").select("Density_Checked_Baggage").eq("Carrier_IATA",iata).maybeSingle()]);
  for(const r of [a,b,c,reviews,density])fail(r.error);
  const raw={defaults:(a.data??[]) as Raw[],weights:(b.data??[]) as Raw[],planning:(c.data??[]) as Raw[]};
  const reviewRows=reviews.data??[];
  const operationMode=reviewRows.find(row=>row.Section_Code==="BAGGAGE_OPERATION_MODE")?.Review_State==="APPLIES"?"ACTUAL" as const:"STANDARD" as const;
  const defaultPerPiece=reviewRows.find(row=>row.Section_Code==="PER_PASSENGER_WEIGHTS")?.Review_State!=="APPLIES";
  const variationMethods=Object.fromEntries(context.variations.flatMap(variation=>{
   const state=reviewRows.find(row=>row.Section_Code===`BAGGAGE_VARIATION_${variation.code}`)?.Review_State;
   const hasTable=raw.weights.some(row=>row.Is_Baseline!==true&&row.Flight_Type_Variation===variation.code);
   const method=hasTable||state==="REVIEWED"?"STANDARD":state==="NOT_APPLICABLE"?"INHERIT":state==="APPLIES"?"ACTUAL":null;
   return method?[[variation.code,method]]:[];
  })) as Partial<Record<string,BaggageVariationMethod>>;
  const revision=createHash("sha256").update(JSON.stringify([raw,context.unit,details.values.volumeUnit,context.classes,context.variations,reviewRows,density.data])).digest("hex");
  return {raw,snapshot:{canView:context.canView,canEdit:context.canEdit,revision,unit:context.unit??"",volumeUnit:details.values.volumeUnit,operationMode,defaultPerPiece,checkedBaggageDensity:density.data?.Density_Checked_Baggage?.toString()??"",classes:context.classes,variations:context.variations,variationMethods,defaults:raw.defaults[0]?record("defaults",raw.defaults[0]):null,weights:raw.weights.map(r=>record("weights",r)).sort((a,b)=>Number(b.baseline)-Number(a.baseline)),planning:raw.planning.map(r=>record("planning",r))}};
 }
 return {async get(iata){return (await read(iata)).snapshot;},async save(iata,revision,section,row,remove){
  const current=await read(iata);if(!current.snapshot.canEdit)throw new BaggageDenied();if(current.snapshot.revision!==revision)throw new BaggageConflict();
  const previous=current.raw[section].find(r=>r[ids[section]]===row.id);
  if(row.id&&!previous)throw new BaggageConflict();
  const values:Raw={Carrier_IATA:iata};for(const [key,col] of Object.entries(maps[section]))values[col]=row.values[key]===""?null:numeric.has(key)?Number(row.values[key]):row.values[key];
  if(!previous){if(remove)throw new BaggageConflict();const result=await api().from(tables[section]).insert(values as {Carrier_IATA:string}).select("Carrier_IATA");fail(result.error);if(result.data?.length!==1)throw new BaggageConflict();return;}
  // Compare every stored field in the same UPDATE/DELETE statement: stale records
  // never overwrite a concurrent edit. Each UI save changes exactly one record.
  let query=remove?api().from(tables[section]).delete():api().from(tables[section]).update(values as {Carrier_IATA:string});
  query=query.eq("Carrier_IATA",iata);
  for(const [col,value] of Object.entries(previous))query=value===null?query.is(col,null):query.eq(col,value);
  const result=await query.select("Carrier_IATA");fail(result.error);if(result.data?.length!==1)throw new BaggageConflict();
 },async saveOperationMode(iata,revision,mode){
  const current=await read(iata);if(!current.snapshot.canEdit)throw new BaggageDenied();if(current.snapshot.revision!==revision)throw new BaggageConflict();
  const result=await api().from("Carrier_Configuration_Review_State").upsert({Carrier_IATA:iata,Page_Code:"B4",Section_Code:"BAGGAGE_OPERATION_MODE",Review_State:mode==="ACTUAL"?"APPLIES":"NOT_APPLICABLE",Reviewed_At:new Date().toISOString()},{onConflict:"Carrier_IATA,Page_Code,Section_Code"}).select("Carrier_IATA");
  fail(result.error);if(result.data?.length!==1)throw new BaggageConflict();
 },async saveApplicability(iata,revision,defaultPerPiece){
  const current=await read(iata);if(!current.snapshot.canEdit)throw new BaggageDenied();if(current.snapshot.revision!==revision)throw new BaggageConflict();
  const result=await api().from("Carrier_Configuration_Review_State").upsert({Carrier_IATA:iata,Page_Code:"B4",Section_Code:"PER_PASSENGER_WEIGHTS",Review_State:defaultPerPiece?"NOT_APPLICABLE":"APPLIES",Reviewed_At:new Date().toISOString()},{onConflict:"Carrier_IATA,Page_Code,Section_Code"}).select("Carrier_IATA");
 fail(result.error);if(result.data?.length!==1)throw new BaggageConflict();
 },async saveVariationMethod(iata,revision,variation,method){
  const current=await read(iata);if(!current.snapshot.canEdit)throw new BaggageDenied();if(current.snapshot.revision!==revision)throw new BaggageConflict();
  if(!current.snapshot.variations.some(item=>item.code===variation)||method!=="STANDARD"&&current.snapshot.weights.some(row=>!row.baseline&&row.values.variation===variation))throw new BaggageInvalid("Check the Flight Variation and remove any saved variation-specific Standard Weight records first.");
  const state=method==="STANDARD"?"REVIEWED":method==="ACTUAL"?"APPLIES":"NOT_APPLICABLE";
  const result=await api().from("Carrier_Configuration_Review_State").upsert({Carrier_IATA:iata,Page_Code:"B4",Section_Code:`BAGGAGE_VARIATION_${variation}`,Review_State:state,Reviewed_At:new Date().toISOString()},{onConflict:"Carrier_IATA,Page_Code,Section_Code"}).select("Carrier_IATA");
  fail(result.error);if(result.data?.length!==1)throw new BaggageConflict();
 }};
}
