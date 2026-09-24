export type BaggageSection = "defaults" | "weights" | "planning";
export type BaggageOperationMode = "STANDARD" | "ACTUAL";
export type BaggageVariationMethod = "INHERIT" | "STANDARD" | "ACTUAL";
export type BaggageRecord = { id: string | null; baseline: boolean; values: Record<string,string> };
export type BaggageSnapshot = { canView:boolean; canEdit:boolean; revision:string; unit:string; volumeUnit:string; operationMode:BaggageOperationMode; defaultPerPiece:boolean; checkedBaggageDensity:string; classes:{code:string;description:string}[]; variations:{code:string;description:string}[]; variationMethods:Partial<Record<string,BaggageVariationMethod>>; defaults:BaggageRecord|null; weights:BaggageRecord[]; planning:BaggageRecord[] };
export class BaggageInvalid extends Error {}
export class BaggageDenied extends Error {}
export class BaggageConflict extends Error {}
export const pieceFields = ["male","female","child","all","summer","winter"] as const;
export const categories = ["ALL","ADULT","MALE","FEMALE","CHILD","INFANT"];
export function newBaggageRecord(section:BaggageSection):BaggageRecord {
 return {id:null,baseline:false,values:section==="defaults"?{method:"STANDARD",male:"",female:"",child:"",all:"",summer:"",winter:"",remarks:""}:section==="weights"?{classCode:"",variation:"",category:"ALL",pieceMethod:"STANDARD",piece:"",passengerMethod:"UNSET",passenger:"",remarks:""}:{classCode:"",variation:"",bags:"",weight:"",volume:"",remarks:""}};
}
export function defaultPlanningRecord(snapshot:BaggageSnapshot):BaggageRecord{
 const standard=snapshot.defaults?.values.all??"";
 return{id:null,baseline:true,values:{...newBaggageRecord("planning").values,bags:"1",weight:standard}};
}
export function validateBaggage(section:BaggageSection,input:unknown,current:BaggageSnapshot):BaggageRecord {
 if(!input||typeof input!=="object") throw new BaggageInvalid("Check your entries.");
 const row=input as BaggageRecord;
 if(!row.values||typeof row.values!=="object"||Array.isArray(row.values)||Object.values(row.values).some(v=>typeof v!=="string")) throw new BaggageInvalid("Check your entries.");
 const saved=section==="defaults"?current.defaults:(section==="weights"?current.weights:current.planning).find(r=>r.id===row.id);
 if(row.id!==null && (!saved||saved.id!==row.id)) throw new BaggageConflict();
 const values={...newBaggageRecord(section).values};
 for(const k of Object.keys(values)) values[k]=row.values[k]??"";
 const result={id:row.id,baseline:saved?.baseline??false,values};
 if(values.remarks.length>2000) throw new BaggageInvalid("Keep remarks within 2,000 characters.");
 function number(key:string,required:boolean,decimal=false){
  const s=values[key];if(!s&&!required)return;
  if(!(decimal?/^\d+(\.\d{1,4})?$/:/^\d+$/).test(s)||!Number.isFinite(Number(s))||Number(s)>(decimal?99999999.9999:2147483647)) throw new BaggageInvalid(decimal?"Enter non-negative planning values with no more than four decimal places.":"Enter non-negative whole-number weights in the required fields.");
 }
 if(section==="defaults"){
  values.method="STANDARD";
  pieceFields.forEach(k=>number(k,["male","female","child"].includes(k)));
 }else{
  if(values.classCode&&!current.classes.some(c=>c.code===values.classCode))throw new BaggageInvalid("Choose a class saved on B1.");
  if(values.variation&&!current.variations.some(v=>v.code===values.variation))throw new BaggageInvalid("Choose a Flight Variation saved on B3.");
  if(section==="planning"){
   number("bags",true,true);number("weight",true,true);number("volume",false,true);
   if(values.volume&&!current.volumeUnit)throw new BaggageInvalid("Save a Volume Unit on B1 before entering volume.");
  }else{
   if(!categories.includes(values.category))throw new BaggageInvalid("Choose a Passenger Category.");
   if(result.baseline&&(values.classCode||values.variation||values.category!=="ALL"))throw new BaggageInvalid("The All Flights baseline identity is fixed.");
   if(!result.baseline){
    values.pieceMethod="STANDARD";
    values.passengerMethod="UNSET";
    values.passenger="";
    if(!values.classCode&&!values.variation)throw new BaggageInvalid("Choose a Class for an All Other Flights override, or choose a Flight Variation.");
    number("piece",true);
   }
  }
  const others=section==="weights"?current.weights:current.planning;
  if(others.some(r=>r.id!==row.id&&r.values.classCode===values.classCode&&r.values.variation===values.variation&&(section==="planning"||r.values.category===values.category)))throw new BaggageInvalid("A record already exists for these selections. Edit the existing record.");
 }
 return result;
}
