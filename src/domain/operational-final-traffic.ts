import{baggageBulkLoadId,defaultBaggageCommodityCode,isBaggageCommodityCode,type BaggageCommodityAllocation,type BaggageCommodityCode}from"@/domain/baggage-commodities";

export const finalPassengerCategories=["male","female","child","infant"] as const;
export type FinalPassengerCategory=typeof finalPassengerCategories[number];
export type OperationalPassengerCounts=Record<FinalPassengerCategory,number>;
export type OperationalFinalPassengerClass={code:string;name:string;booked:number;final:number};
export type OperationalFinalPassengerArea={areaId:string;seats:number;passengers:number};
export type OperationalBaggageContent={loadId:string;kind:"ULD"|"BULK";uldCode:string|null;uldNumber:string|null;classCode?:string|null;commodityCode?:BaggageCommodityCode;commodities?:BaggageCommodityAllocation[];pieces:number;netWeight:number};
export type OperationalFinalTraffic={applicable:boolean;canEdit:boolean;version:number;status:"EMPTY"|"TRAFFIC_FINAL"|"BAGGAGE_FINAL";passengerCounts:OperationalPassengerCounts;classes:OperationalFinalPassengerClass[];areas:OperationalFinalPassengerArea[];totalPassengers:number;passengerWeight:number;baggagePieces:number;baggageNetWeight:number;contents:OperationalBaggageContent[];updatedAt:string|null;finalisedAt:string|null};
export type OperationalFinalTrafficInput={passengerCounts:OperationalPassengerCounts;classes:Array<{code:string;final:number}>;areas:OperationalFinalPassengerArea[];baggagePieces:number;baggageNetWeight:number;contents:OperationalBaggageContent[]};
export class OperationalFinalTrafficInvalid extends Error{}
export function passengerCountWithInfants(counts:OperationalPassengerCounts){const seated=counts.male+counts.female+counts.child;return counts.infant?`${seated.toLocaleString()}+${counts.infant.toLocaleString()}`:seated.toLocaleString()}

export const baggageWeightFromPieces=(pieces:unknown,weightPerPiece:number)=>{
 const count=Number(pieces);return Number.isFinite(count)&&count>=0&&Number.isFinite(weightPerPiece)&&weightPerPiece>=0?Math.round(count*weightPerPiece):0;
};

export function baggageBulkRemainder(totalPieces:unknown,totalNetWeight:unknown,uldContents:Array<{pieces:number;netWeight:number}>,weightPerPiece:number|null=null){
 const pieces=Math.max(0,Number(totalPieces)||0),netWeight=Math.max(0,Number(totalNetWeight)||0),uldPieces=uldContents.reduce((sum,item)=>sum+(Number(item.pieces)||0),0),uldNetWeight=uldContents.reduce((sum,item)=>sum+(Number(item.netWeight)||0),0),remainderPieces=Math.max(0,pieces-uldPieces),standardWeight=weightPerPiece!==null&&Number.isFinite(weightPerPiece)&&weightPerPiece>=0?weightPerPiece:null;
 return{pieces:remainderPieces,netWeight:standardWeight===null?Math.max(0,netWeight-uldNetWeight):baggageWeightFromPieces(remainderPieces,standardWeight),overallocatedPieces:Math.max(0,uldPieces-pieces),overallocatedNetWeight:Math.max(0,uldNetWeight-netWeight)};
}
export function baggageContentsReady(value:Pick<OperationalFinalTraffic,"baggagePieces"|"baggageNetWeight"|"contents">){
 const pieces=value.contents.reduce((sum,item)=>sum+item.pieces,0),weight=value.contents.reduce((sum,item)=>sum+item.netWeight,0),uldNumbers=value.contents.filter(item=>item.kind==="ULD").map(item=>item.uldNumber?.trim().toUpperCase()??"");
 return pieces===value.baggagePieces&&weight===value.baggageNetWeight&&uldNumbers.every(Boolean)&&new Set(uldNumbers).size===uldNumbers.length;
}

export function finalTrafficRequiresLoadPlanActualisation(
 traffic:Pick<OperationalFinalTraffic,"status"|"updatedAt">,
 plan:{createdAt:string|null;actualisedAt:string|null},
){
 if(traffic.status!=="BAGGAGE_FINAL"||!traffic.updatedAt)return false;
 const planTimestamp=plan.actualisedAt??plan.createdAt;
 return Boolean(planTimestamp&&new Date(traffic.updatedAt).getTime()>new Date(planTimestamp).getTime());
}

const whole=(value:unknown,label:string,max=999)=>{const number=Number(value);if(!Number.isSafeInteger(number)||number<0||number>max)throw new OperationalFinalTrafficInvalid(`${label} must be a whole number between 0 and ${max}.`);return number};
const weight=(value:unknown,label:string)=>{const number=Number(value);if(!Number.isFinite(number)||number<0||number>100000)throw new OperationalFinalTrafficInvalid(`Enter a valid ${label}.`);return Math.round(number)};
const counts=(item:Record<string,unknown>,label:string)=>Object.fromEntries(finalPassengerCategories.map(category=>[category,whole(item[category],`${label} ${category} passengers`)])) as OperationalPassengerCounts;
const contentCommodities=(item:Record<string,unknown>,pieces:number,netWeight:number)=>{const raw=Array.isArray(item.commodities)&&item.commodities.length?item.commodities:[{classCode:item.classCode??null,commodityCode:item.commodityCode??defaultBaggageCommodityCode(String(item.classCode??"")),pieces,netWeight}];if(raw.length>4)throw new OperationalFinalTrafficInvalid("A baggage load may contain no more than four baggage commodities.");const seen=new Set<string>(),values=raw.map(value=>{const row=value as Record<string,unknown>,classCode=String(row.classCode??"").trim().toUpperCase()||null,commodityCode=String(row.commodityCode??"").trim().toUpperCase(),rowPieces=whole(row.pieces,"Baggage commodity pieces",9999),rowWeight=weight(row.netWeight,"baggage commodity weight"),key=`${classCode??""}:${commodityCode}`;if(classCode&&!/^[A-Z]$/.test(classCode)||!isBaggageCommodityCode(commodityCode)||seen.has(key))throw new OperationalFinalTrafficInvalid("Check each baggage commodity within the load.");seen.add(key);return{classCode,commodityCode,pieces:rowPieces,netWeight:rowWeight}});if(values.reduce((sum,row)=>sum+row.pieces,0)!==pieces||values.reduce((sum,row)=>sum+row.netWeight,0)!==netWeight)throw new OperationalFinalTrafficInvalid("Reconcile each load's commodity contents with its pieces and net weight.");return values};
export function validateOperationalFinalTraffic(input:unknown,finalise:boolean):OperationalFinalTrafficInput{
 if(!input||typeof input!=="object")throw new OperationalFinalTrafficInvalid("Enter the final passenger and baggage figures.");
 const row=input as Record<string,unknown>;if(!Array.isArray(row.classes)||!Array.isArray(row.areas)||!Array.isArray(row.contents))throw new OperationalFinalTrafficInvalid("Enter the final passenger and baggage figures.");
 const passengerCounts=counts((row.passengerCounts??{}) as Record<string,unknown>,"Final");
 const seatedPassengers=passengerCounts.male+passengerCounts.female+passengerCounts.child;
 const seenClasses=new Set<string>(),classes=row.classes.map(value=>{const item=value as Record<string,unknown>,code=String(item?.code??"").trim().toUpperCase(),final=whole(item.final,`Final class ${code}`,999);if(!/^[A-Z]$/.test(code)||seenClasses.has(code))throw new OperationalFinalTrafficInvalid("Each passenger class may be entered once.");seenClasses.add(code);return{code,final}});
 const seenAreas=new Set<string>(),areas=row.areas.map(value=>{const item=value as Record<string,unknown>,areaId=String(item?.areaId??"").trim().toUpperCase(),seats=whole(item.seats,`Seats in cabin area ${areaId}`,999),passengers=whole(item.passengers,`Passengers in cabin area ${areaId}`,999);if(!areaId||seenAreas.has(areaId))throw new OperationalFinalTrafficInvalid("Each cabin area may be entered once.");seenAreas.add(areaId);if(passengers>seats)throw new OperationalFinalTrafficInvalid(`Cabin area ${areaId} exceeds its ${seats} installed seats.`);return{areaId,seats,passengers}});
 if(classes.reduce((sum,item)=>sum+item.final,0)!==seatedPassengers)throw new OperationalFinalTrafficInvalid("Reconcile the final passenger totals by class with Male, Female and Child.");
 if(areas.reduce((sum,item)=>sum+item.passengers,0)!==seatedPassengers)throw new OperationalFinalTrafficInvalid("Reconcile the cabin-area distribution with the final seated passenger total.");
 const baggagePieces=whole(row.baggagePieces,"Final baggage pieces",9999),baggageNetWeight=weight(row.baggageNetWeight,"final baggage weight"),seenLoads=new Set<string>(),seenUlds=new Set<string>();
 const contents=row.contents.map(value=>{const item=value as Record<string,unknown>,loadId=String(item?.loadId??"").trim(),kind=String(item?.kind??"").toUpperCase(),uldCode=String(item?.uldCode??"").trim().toUpperCase()||null,uldNumber=String(item?.uldNumber??"").trim().toUpperCase()||null,pieces=whole(item.pieces,"Baggage pieces",9999),netWeight=weight(item.netWeight,"baggage-content weight");if(!loadId||seenLoads.has(loadId)||!(["ULD","BULK"] as string[]).includes(kind))throw new OperationalFinalTrafficInvalid("Check the baggage-content rows.");if(uldNumber&&!/^[A-Z0-9][A-Z0-9-]{2,14}$/.test(uldNumber))throw new OperationalFinalTrafficInvalid("Enter a valid baggage ULD number.");if(uldNumber&&seenUlds.has(uldNumber))throw new OperationalFinalTrafficInvalid("Each baggage ULD number must be unique.");if(kind==="ULD"&&finalise&&!uldNumber)throw new OperationalFinalTrafficInvalid("Enter the actual number of every baggage ULD before finalising.");const commodities=contentCommodities(item,pieces,netWeight),classCode=commodities.length===1?commodities[0].classCode:null,commodityCode=commodities.every(row=>row.commodityCode===commodities[0].commodityCode)?commodities[0].commodityCode:"B";if(kind==="BULK"&&((loadId==="PLANNED_BAGGAGE:BULK"&&commodityCode!=="B")||(loadId!=="PLANNED_BAGGAGE:BULK"&&loadId!==baggageBulkLoadId(commodityCode))||commodities.some(row=>row.commodityCode!==commodityCode)))throw new OperationalFinalTrafficInvalid("Keep each final Bulk baggage category as a separate load.");seenLoads.add(loadId);if(uldNumber)seenUlds.add(uldNumber);return{loadId,kind:kind as"ULD"|"BULK",uldCode,uldNumber,classCode,commodityCode,commodities,pieces,netWeight}});
 const uldContents=contents.filter(item=>item.kind==="ULD"),bulk=contents.filter(item=>item.kind==="BULK"),remainder=baggageBulkRemainder(baggagePieces,baggageNetWeight,uldContents),bulkPieces=bulk.reduce((sum,item)=>sum+item.pieces,0),bulkWeight=bulk.reduce((sum,item)=>sum+item.netWeight,0);
 if(bulk.length>5||new Set(bulk.map(item=>item.commodityCode)).size!==bulk.length)throw new OperationalFinalTrafficInvalid("Baggage may include one Bulk load per baggage category.");
 if(bulkPieces!==remainder.pieces||bulkWeight!==remainder.netWeight)throw new OperationalFinalTrafficInvalid("Bulk baggage must be the calculated remainder after the ULD contents.");
 if(finalise){const pieces=contents.reduce((sum,item)=>sum+item.pieces,0),net=contents.reduce((sum,item)=>sum+item.netWeight,0);if(pieces!==baggagePieces||net!==baggageNetWeight)throw new OperationalFinalTrafficInvalid("Reconcile the ULD and Bulk contents to the final baggage pieces and weight before finalising.");}
 return{passengerCounts,classes,areas,baggagePieces,baggageNetWeight,contents};
}
