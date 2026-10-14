export const finalPassengerCategories=["male","female","child","infant"] as const;
export type FinalPassengerCategory=typeof finalPassengerCategories[number];
export type OperationalPassengerCounts=Record<FinalPassengerCategory,number>;
export type OperationalFinalPassengerClass={code:string;name:string;booked:number;final:number;male:number;female:number;child:number;infant:number;planningWeight:number|null;passengerWeight:number|null;maleWeight:number|null;femaleWeight:number|null;childWeight:number|null;infantWeight:number|null};
export type OperationalFinalPassengerArea={areaId:string;seats:number;male:number;female:number;child:number;infant:number};
export type OperationalBaggageContent={loadId:string;kind:"ULD"|"BULK";uldCode:string|null;uldNumber:string|null;pieces:number;netWeight:number};
export type OperationalFinalTraffic={applicable:boolean;canEdit:boolean;version:number;status:"EMPTY"|"TRAFFIC_FINAL"|"BAGGAGE_FINAL";classes:OperationalFinalPassengerClass[];areas:OperationalFinalPassengerArea[];totalPassengers:number;passengerWeight:number;baggagePieces:number;baggageNetWeight:number;contents:OperationalBaggageContent[];updatedAt:string|null;finalisedAt:string|null};
export type OperationalFinalTrafficInput={classes:Array<{code:string}&OperationalPassengerCounts>;areas:OperationalFinalPassengerArea[];baggagePieces:number;baggageNetWeight:number;contents:OperationalBaggageContent[]};
export class OperationalFinalTrafficInvalid extends Error{}

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
export function validateOperationalFinalTraffic(input:unknown,finalise:boolean):OperationalFinalTrafficInput{
 if(!input||typeof input!=="object")throw new OperationalFinalTrafficInvalid("Enter the final passenger and baggage figures.");
 const row=input as Record<string,unknown>;if(!Array.isArray(row.classes)||!Array.isArray(row.areas)||!Array.isArray(row.contents))throw new OperationalFinalTrafficInvalid("Enter the final passenger and baggage figures.");
 const seenClasses=new Set<string>(),classes=row.classes.map(value=>{const item=value as Record<string,unknown>,code=String(item?.code??"").trim().toUpperCase();if(!/^[A-Z]$/.test(code)||seenClasses.has(code))throw new OperationalFinalTrafficInvalid("Each passenger class may be entered once.");seenClasses.add(code);return{code,...counts(item,`Final class ${code}`)}});
 const seenAreas=new Set<string>(),areas=row.areas.map(value=>{const item=value as Record<string,unknown>,areaId=String(item?.areaId??"").trim().toUpperCase(),seats=whole(item.seats,`Seats in cabin area ${areaId}`,999);if(!areaId||seenAreas.has(areaId))throw new OperationalFinalTrafficInvalid("Each cabin area may be entered once.");seenAreas.add(areaId);const values=counts(item,`Cabin area ${areaId}`);if(values.male+values.female+values.child>seats)throw new OperationalFinalTrafficInvalid(`Cabin area ${areaId} exceeds its ${seats} installed seats.`);return{areaId,seats,...values}});
 const classTotals=Object.fromEntries(finalPassengerCategories.map(category=>[category,classes.reduce((sum,item)=>sum+item[category],0)])) as OperationalPassengerCounts,areaTotals=Object.fromEntries(finalPassengerCategories.map(category=>[category,areas.reduce((sum,item)=>sum+item[category],0)])) as OperationalPassengerCounts;
 if(finalPassengerCategories.some(category=>classTotals[category]!==areaTotals[category]))throw new OperationalFinalTrafficInvalid("Reconcile the passenger totals by Male, Female, Child and Infant with the cabin-area distribution.");
 const baggagePieces=whole(row.baggagePieces,"Final baggage pieces",9999),baggageNetWeight=weight(row.baggageNetWeight,"final baggage weight"),seenLoads=new Set<string>(),seenUlds=new Set<string>();
 const contents=row.contents.map(value=>{const item=value as Record<string,unknown>,loadId=String(item?.loadId??"").trim(),kind=String(item?.kind??"").toUpperCase(),uldCode=String(item?.uldCode??"").trim().toUpperCase()||null,uldNumber=String(item?.uldNumber??"").trim().toUpperCase()||null;if(!loadId||seenLoads.has(loadId)||!(["ULD","BULK"] as string[]).includes(kind))throw new OperationalFinalTrafficInvalid("Check the baggage-content rows.");if(kind==="BULK"&&loadId!=="PLANNED_BAGGAGE:BULK")throw new OperationalFinalTrafficInvalid("Only one final Bulk baggage load may be recorded.");if(uldNumber&&!/^[A-Z0-9][A-Z0-9-]{2,14}$/.test(uldNumber))throw new OperationalFinalTrafficInvalid("Enter a valid baggage ULD number.");if(uldNumber&&seenUlds.has(uldNumber))throw new OperationalFinalTrafficInvalid("Each baggage ULD number must be unique.");if(kind==="ULD"&&finalise&&!uldNumber)throw new OperationalFinalTrafficInvalid("Enter the actual number of every baggage ULD before finalising.");seenLoads.add(loadId);if(uldNumber)seenUlds.add(uldNumber);return{loadId,kind:kind as"ULD"|"BULK",uldCode,uldNumber,pieces:whole(item.pieces,"Baggage pieces",9999),netWeight:weight(item.netWeight,"baggage-content weight")}});
 if(contents.filter(item=>item.kind==="BULK").length>1)throw new OperationalFinalTrafficInvalid("Only one final Bulk baggage load may be recorded.");
 const uldContents=contents.filter(item=>item.kind==="ULD"),bulk=contents.find(item=>item.kind==="BULK"),remainder=baggageBulkRemainder(baggagePieces,baggageNetWeight,uldContents);
 if((remainder.pieces>0&&(!bulk||bulk.pieces!==remainder.pieces||bulk.netWeight!==remainder.netWeight))||(remainder.pieces===0&&bulk&&(bulk.pieces!==0||bulk.netWeight!==0)))throw new OperationalFinalTrafficInvalid("Bulk baggage must be the calculated remainder after the ULD contents.");
 if(finalise){const pieces=contents.reduce((sum,item)=>sum+item.pieces,0),net=contents.reduce((sum,item)=>sum+item.netWeight,0);if(pieces!==baggagePieces||net!==baggageNetWeight)throw new OperationalFinalTrafficInvalid("Reconcile the ULD and Bulk contents to the final baggage pieces and weight before finalising.");}
 return{classes,areas,baggagePieces,baggageNetWeight,contents};
}
