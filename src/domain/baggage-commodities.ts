export const baggageCommodityCodes=["B","BF","BJ","BP","BY"] as const;
export type BaggageCommodityCode=typeof baggageCommodityCodes[number];

export type OperationalBaggageClass={
 classCode:string;
 className:string;
 commodityCode:BaggageCommodityCode;
 passengers:number;
 bagsPerPassenger:number|null;
 plannedPieces:number;
 weightPerPassenger:number|null;
 plannedWeight:number;
 plannedVolume:number|null;
};

export type BaggageCommodityAllocation={
 classCode:string|null;
 commodityCode:BaggageCommodityCode;
 pieces:number;
 netWeight:number;
};

export type MixedBaggageContent={
 loadId:string;
 kind:"ULD"|"BULK";
 uldCode:string|null;
 uldNumber:string|null;
 classCode?:string|null;
 commodityCode?:BaggageCommodityCode;
 commodities:BaggageCommodityAllocation[];
 pieces:number;
 netWeight:number;
};

export function isBaggageCommodityCode(value:unknown):value is BaggageCommodityCode{
 return baggageCommodityCodes.includes(String(value??"").trim().toUpperCase() as BaggageCommodityCode);
}

export function defaultBaggageCommodityCode(classCode:string,className=""):BaggageCommodityCode{
 const code=classCode.trim().toUpperCase(),name=className.trim().toUpperCase();
 if(name.includes("FIRST")||code==="F")return"BF";
 if(name.includes("PREMIUM")||code==="W"||code==="P")return"BP";
 if(name.includes("BUSINESS")||code==="C"||code==="J")return"BJ";
 if(name.includes("ECONOMY")||code==="Y")return"BY";
 return"B";
}

export function baggageCommodityAllocations(row:{classCode?:string|null;commodityCode?:unknown;commodities?:unknown;pieces:unknown;netWeight:unknown}):BaggageCommodityAllocation[]{
 if(Array.isArray(row.commodities)&&row.commodities.length)return row.commodities.map(value=>{const item=value as Partial<BaggageCommodityAllocation>,classCode=String(item.classCode??"").trim().toUpperCase()||null,commodityCode=isBaggageCommodityCode(item.commodityCode)?String(item.commodityCode).trim().toUpperCase() as BaggageCommodityCode:defaultBaggageCommodityCode(classCode??"");return{classCode,commodityCode,pieces:Math.max(0,Math.floor(Number(item.pieces)||0)),netWeight:Math.max(0,Math.round(Number(item.netWeight)||0))}});
 const classCode=String(row.classCode??"").trim().toUpperCase()||null,commodityCode=isBaggageCommodityCode(row.commodityCode)?String(row.commodityCode).trim().toUpperCase() as BaggageCommodityCode:defaultBaggageCommodityCode(classCode??"");
 return[{classCode,commodityCode,pieces:Math.max(0,Math.floor(Number(row.pieces)||0)),netWeight:Math.max(0,Math.round(Number(row.netWeight)||0))}];
}

export function baggageCommoditySummary(row:{classCode?:string|null;commodityCode?:unknown;commodities?:unknown;pieces:unknown;netWeight:unknown}){
 return baggageCommodityAllocations(row).filter(item=>item.pieces>0||item.netWeight>0).map(item=>`${item.commodityCode} ${item.pieces} PCS`).join(" · ")||"B 0 PCS";
}

export const baggageBulkLoadId=(commodityCode:BaggageCommodityCode)=>`PLANNED_BAGGAGE:${commodityCode}:BULK`;

const split=(total:number,count:number)=>count?Array.from({length:count},(_,index)=>Math.floor(total/count)+(index<total%count?1:0)):[];

export function mixedBaggageContents(classes:OperationalBaggageClass[],uldPieceTotals:number[],uldCode:string|null,uldNetWeightTotals?:number[]):MixedBaggageContent[]{
 const active=classes.filter(row=>row.plannedPieces>0||row.plannedWeight>0),states=active.map(row=>({...row,allocatedPieces:0,allocatedWeight:0})),contents:MixedBaggageContent[]=[];let classIndex=0;
 const take=(state:typeof states[number],requested:number)=>{const remaining=Math.max(0,state.plannedPieces-state.allocatedPieces),pieces=Math.min(remaining,requested),nextPieces=state.allocatedPieces+pieces,cumulativeWeight=state.plannedPieces?Math.round(state.plannedWeight*nextPieces/state.plannedPieces):0,netWeight=Math.max(0,cumulativeWeight-state.allocatedWeight);state.allocatedPieces=nextPieces;state.allocatedWeight=cumulativeWeight;return{classCode:state.classCode||null,commodityCode:state.commodityCode,pieces,netWeight}};
 for(const[index,rawTarget]of uldPieceTotals.entries()){
  let needed=Math.max(0,Math.floor(rawTarget)||0);const commodities:BaggageCommodityAllocation[]=[];
  while(needed>0&&classIndex<states.length){const state=states[classIndex],allocation=take(state,needed);if(allocation.pieces>0||allocation.netWeight>0)commodities.push(allocation);needed-=allocation.pieces;if(state.allocatedPieces>=state.plannedPieces)classIndex++;else break}
  if(needed>0){const state=states.at(-1),classCode=state?.classCode||null,commodityCode=state?.commodityCode??"B",weightPerPiece=state?.plannedPieces?state.plannedWeight/state.plannedPieces:0;commodities.push({classCode,commodityCode,pieces:needed,netWeight:Math.round(needed*weightPerPiece)})}
  if(uldNetWeightTotals?.[index]!==undefined&&commodities.length){let delta=Math.max(0,Math.round(uldNetWeightTotals[index]))-commodities.reduce((sum,item)=>sum+item.netWeight,0);for(let commodityIndex=commodities.length-1;commodityIndex>=0&&delta!==0;commodityIndex--){const commodity=commodities[commodityIndex],change=delta<0?-Math.min(commodity.netWeight,-delta):delta;commodity.netWeight+=change;delta-=change;const state=states.find(item=>(item.classCode||null)===commodity.classCode&&item.commodityCode===commodity.commodityCode);if(state)state.allocatedWeight+=change}}
  contents.push({loadId:`PLANNED_BAGGAGE:${index+1}`,kind:"ULD",uldCode,uldNumber:null,classCode:commodities.length===1?commodities[0].classCode:null,commodityCode:commodities.length===1?commodities[0].commodityCode:"B",commodities,pieces:commodities.reduce((sum,item)=>sum+item.pieces,0),netWeight:commodities.reduce((sum,item)=>sum+item.netWeight,0)});
 }
 const bulkByCommodity=new Map<BaggageCommodityCode,BaggageCommodityAllocation[]>();
 for(const state of states){const pieces=Math.max(0,state.plannedPieces-state.allocatedPieces),netWeight=Math.max(0,state.plannedWeight-state.allocatedWeight);if(pieces>0||netWeight>0){const allocation={classCode:state.classCode||null,commodityCode:state.commodityCode,pieces,netWeight},rows=bulkByCommodity.get(state.commodityCode)??[];rows.push(allocation);bulkByCommodity.set(state.commodityCode,rows)}}
 for(const[commodityCode,commodities]of bulkByCommodity){contents.push({loadId:baggageBulkLoadId(commodityCode),kind:"BULK",uldCode:null,uldNumber:null,classCode:commodities.length===1?commodities[0].classCode:null,commodityCode,commodities,pieces:commodities.reduce((sum,item)=>sum+item.pieces,0),netWeight:commodities.reduce((sum,item)=>sum+item.netWeight,0)})}
 return contents;
}

export function baggageContentsForUldCount(classes:OperationalBaggageClass[],uldCount:number,uldCode:string|null,pieceCapacity:number|null,pieceTargets?:readonly number[]){
 const active=classes.filter(row=>row.plannedPieces>0),totalPieces=active.reduce((sum,row)=>sum+Math.max(0,row.plannedPieces),0),count=Math.max(0,Math.floor(uldCount)),capacity=pieceCapacity&&pieceCapacity>0?pieceCapacity:null;
 const separated=capacity?active.flatMap(row=>{let remaining=row.plannedPieces;return Array.from({length:Math.ceil(remaining/capacity)},()=>{const pieces=Math.min(capacity,remaining);remaining-=pieces;return pieces})}):split(totalPieces,count);
 // The A350 planning service supplies targets checked against pieces, gross
 // weight and volume, including a shared BF/BJ ULD. Other aircraft retain their policy.
 const targets=pieceTargets?Array.from({length:count},(_,index)=>pieceTargets[index]??0):capacity?Array.from({length:count},(_,index)=>separated[index]??0):separated;
 return mixedBaggageContents(classes,targets,uldCode);
}

export function adjustBaggageClassesToTotals(classes:OperationalBaggageClass[],totalPieces:number,totalWeight:number){
 const adjusted=classes.filter(row=>row.plannedPieces>0||row.plannedWeight>0).map(row=>({...row}));
 if(!adjusted.length)return[{classCode:"",className:"All classes",commodityCode:"B" as const,passengers:0,bagsPerPassenger:null,plannedPieces:Math.max(0,Math.floor(totalPieces)),weightPerPassenger:null,plannedWeight:Math.max(0,Math.round(totalWeight)),plannedVolume:null}];
 let pieceDelta=Math.max(0,Math.floor(totalPieces))-adjusted.reduce((sum,row)=>sum+row.plannedPieces,0),weightDelta=Math.max(0,Math.round(totalWeight))-adjusted.reduce((sum,row)=>sum+row.plannedWeight,0);
 for(let index=adjusted.length-1;index>=0;index--){const row=adjusted[index],pieceChange=pieceDelta<0?-Math.min(row.plannedPieces,-pieceDelta):index===adjusted.length-1?pieceDelta:0,weightChange=weightDelta<0?-Math.min(row.plannedWeight,-weightDelta):index===adjusted.length-1?weightDelta:0;row.plannedPieces+=pieceChange;row.plannedWeight+=weightChange;pieceDelta-=pieceChange;weightDelta-=weightChange}
 return adjusted;
}

export function normalizeBaggageContent<T extends{loadId:string;kind:"ULD"|"BULK";uldCode:string|null;uldNumber:string|null;classCode?:string|null;commodityCode?:BaggageCommodityCode;commodities?:unknown;pieces:number;netWeight:number}>(row:T):T&{classCode:string|null;commodityCode:BaggageCommodityCode;commodities:BaggageCommodityAllocation[]}{
 const commodities=baggageCommodityAllocations(row),classCode=commodities.length===1?commodities[0].classCode:null,commodityCode=commodities.length===1?commodities[0].commodityCode:"B";
 return{...row,classCode,commodityCode,commodities};
}
