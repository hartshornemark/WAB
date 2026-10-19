export type SolverLoad={
 id:string;
 description:string;
 commodity?:"BAGGAGE"|"CARGO"|"MAIL"|"OTHER"|"EMPTY";
 commodityCode?:string;
 baggageCommodities?:Array<{code:string;pieces:number;netWeight:number}>;
 loadType:"ULD"|"BULK";
 weightKg:number;
 emptyUld?:boolean;
 volumeLitres:number|null;
 uldCode:string|null;
 unloadOrder:number;
 lockedPositionId:string|null;
 specialLoadCodes:string[];
 specialLoadDetails?:string[];
 dangerousGoodsClasses:string[];
};

export type SolverPosition={
 id:string;
 description:string;
 loadType:"ULD"|"BULK";
 acceptedUldCodes:string[];
 maximumWeightKg:number;
 maximumVolumeLitres:number|null;
 occupiedBayIds:string[];
 handlingRank:number;
 simplicityGroup:string;
 indexPerKgScaled:number;
 holdId:string;
 locationRef:string|null;
 compartmentRef?:string|null;
 doorAnchor?:boolean;
 doorOrientation?:"L"|"R"|"C";
 segregationGroup:string;
 balanceArm:number|null;
 deckCode:string;
};

export type SolverIncompatibility={left:string;right:string;reason:string};
export type SolverSpecialLoadLimit={code:string;holdId:string;locationRef:string|null;maximumQuantity:number};

export type LoadPlanningProblem={
 version:1;
 timeLimitSeconds:number;
 idealTrimIndexScaled:number|null;
 loads:SolverLoad[];
 positions:SolverPosition[];
 incompatiblePairs:SolverIncompatibility[];
 specialLoadLimits:SolverSpecialLoadLimit[];
};

export type LoadPlanningAssignment={loadId:string;positionId:string;loadReference?:string|null};
export type LoadPlanningSolution={
 status:"OPTIMAL"|"FEASIBLE"|"INFEASIBLE"|"UNKNOWN";
 engine:string;
 solveMilliseconds:number;
 assignments:LoadPlanningAssignment[];
 sequencePenalty:number|null;
 usedSimplicityGroups:number|null;
 trimDeviationScaled:number|null;
 messages:string[];
};

export class LoadPlanningProblemInvalid extends Error{}

const whole=(value:unknown,label:string,minimum=0)=>{const number=Number(value);if(!Number.isSafeInteger(number)||number<minimum)throw new LoadPlanningProblemInvalid(`${label} must be a whole number of at least ${minimum}.`);return number};
const id=(value:unknown,label:string)=>{const result=String(value??"").trim();if(!result||result.length>100)throw new LoadPlanningProblemInvalid(`${label} is required and must not exceed 100 characters.`);return result};
const optionalId=(value:unknown,label:string)=>value===null||value===undefined||String(value).trim()===""?null:id(value,label);
const uniqueIds=(value:unknown,label:string)=>[...new Set((Array.isArray(value)?value:[]).map(item=>id(item,label).toUpperCase()))];
const optionalWhole=(value:unknown,label:string,minimum=0)=>value===null||value===undefined?null:whole(value,label,minimum);
const loadTokens=(load:SolverLoad)=>new Set([...load.specialLoadCodes.map(code=>`CODE:${code}`),...load.dangerousGoodsClasses.map(code=>`DGR:${code}`)]);

export function validateLoadPlanningProblem(value:unknown):LoadPlanningProblem{
 const row=value as Partial<LoadPlanningProblem>;
 if(row?.version!==1||!Array.isArray(row.loads)||!Array.isArray(row.positions)||row.idealTrimIndexScaled===undefined)throw new LoadPlanningProblemInvalid("Check the AUTOLOAD problem structure.");
 if(!row.loads.length)throw new LoadPlanningProblemInvalid("AUTOLOAD requires at least one released load.");
 if(!row.positions.length)throw new LoadPlanningProblemInvalid("AUTOLOAD requires at least one configured loading position.");
 const loadIds=new Set<string>(),positionIds=new Set<string>();
 const positions=row.positions.map((position,index)=>{const positionId=id(position?.id,`Position ${index+1} ID`),loadType=position.loadType;if(positionIds.has(positionId))throw new LoadPlanningProblemInvalid(`Position ${positionId} is duplicated.`);if(loadType!=="ULD"&&loadType!=="BULK")throw new LoadPlanningProblemInvalid(`Position ${positionId} must be ULD or Bulk.`);positionIds.add(positionId);const occupiedBayIds=[...new Set((position.occupiedBayIds??[]).map(value=>id(value,`Position ${positionId} occupied bay`)))];if(!occupiedBayIds.length)throw new LoadPlanningProblemInvalid(`Position ${positionId} must occupy at least one physical bay.`);const balanceArm=position.balanceArm===null?null:Number(position.balanceArm),compartmentRef=optionalId(position.compartmentRef,`Position ${positionId} compartment`),doorOrientation=position.doorOrientation===undefined?undefined:String(position.doorOrientation).trim().toUpperCase();if(balanceArm!==null&&!Number.isFinite(balanceArm))throw new LoadPlanningProblemInvalid(`Position ${positionId} balance arm must be a finite number.`);if(doorOrientation!==undefined&&!(["L","R","C"] as string[]).includes(doorOrientation))throw new LoadPlanningProblemInvalid(`Position ${positionId} has an invalid door orientation.`);return{id:positionId,description:String(position.description??positionId),loadType,acceptedUldCodes:uniqueIds(position.acceptedUldCodes,`Position ${positionId} ULD code`),maximumWeightKg:whole(position.maximumWeightKg,`Position ${positionId} maximum weight`,1),maximumVolumeLitres:optionalWhole(position.maximumVolumeLitres,`Position ${positionId} maximum volume`,1),occupiedBayIds,handlingRank:whole(position.handlingRank,`Position ${positionId} handling rank`),simplicityGroup:id(position.simplicityGroup,`Position ${positionId} simplicity group`),indexPerKgScaled:whole(Math.abs(position.indexPerKgScaled),`Position ${positionId} index scale`)*(position.indexPerKgScaled<0?-1:1),holdId:id(position.holdId,`Position ${positionId} hold`),locationRef:optionalId(position.locationRef,`Position ${positionId} location`),...(compartmentRef?{compartmentRef}:{}),...(position.doorAnchor?{doorAnchor:true}:{}),...(doorOrientation?{doorOrientation:doorOrientation as "L"|"R"|"C"}:{}),segregationGroup:id(position.segregationGroup,`Position ${positionId} segregation group`),balanceArm,deckCode:id(position.deckCode,`Position ${positionId} deck`).toUpperCase()} as SolverPosition});
 const loads=row.loads.map((load,index)=>{const loadId=id(load?.id,`Load ${index+1} ID`),loadType=load.loadType;if(loadIds.has(loadId))throw new LoadPlanningProblemInvalid(`Load ${loadId} is duplicated.`);if(loadType!=="ULD"&&loadType!=="BULK")throw new LoadPlanningProblemInvalid(`Load ${loadId} must be ULD or Bulk.`);loadIds.add(loadId);const uldCode=load.uldCode===null?null:id(load.uldCode,`Load ${loadId} ULD code`).toUpperCase(),lockedPositionId=load.lockedPositionId===null?null:id(load.lockedPositionId,`Load ${loadId} locked position`),commodityCode=load.commodityCode===undefined?undefined:id(load.commodityCode,`Load ${loadId} commodity code`).toUpperCase();if(commodityCode&&!/^[A-Z]{1,3}$/.test(commodityCode))throw new LoadPlanningProblemInvalid(`Load ${loadId} has an invalid commodity code.`);const baggageCommodities=Array.isArray(load.baggageCommodities)?load.baggageCommodities.map((item,itemIndex)=>{const code=id(item?.code,`Load ${loadId} baggage commodity ${itemIndex+1}`).toUpperCase();if(!/^B(?:F|J|P|Y)?$/.test(code))throw new LoadPlanningProblemInvalid(`Load ${loadId} has an invalid baggage commodity.`);return{code,pieces:whole(item.pieces,`Load ${loadId} ${code} pieces`),netWeight:whole(item.netWeight,`Load ${loadId} ${code} net weight`)}}):[];if(baggageCommodities.length>4||new Set(baggageCommodities.map(item=>item.code)).size!==baggageCommodities.length)throw new LoadPlanningProblemInvalid(`Load ${loadId} must contain no more than four distinct baggage commodities.`);if(loadType==="ULD"&&!uldCode)throw new LoadPlanningProblemInvalid(`ULD load ${loadId} requires a ULD code.`);if(loadType==="BULK"&&uldCode)throw new LoadPlanningProblemInvalid(`Bulk load ${loadId} cannot have a ULD code.`);if(lockedPositionId&&!positionIds.has(lockedPositionId))throw new LoadPlanningProblemInvalid(`Load ${loadId} is locked to unknown position ${lockedPositionId}.`);return{id:loadId,description:String(load.description??loadId),...(load.commodity?{commodity:load.commodity}:{}),...(commodityCode?{commodityCode}:{}),...(baggageCommodities.length?{baggageCommodities}:{}),loadType,weightKg:whole(load.weightKg,`Load ${loadId} weight`,1),...(load.emptyUld?{emptyUld:true}:{}),volumeLitres:optionalWhole(load.volumeLitres,`Load ${loadId} volume`),uldCode,unloadOrder:whole(load.unloadOrder,`Load ${loadId} unloading order`),lockedPositionId,specialLoadCodes:uniqueIds(load.specialLoadCodes,`Load ${loadId} special-load code`),...(Array.isArray(load.specialLoadDetails)?{specialLoadDetails:uniqueIds(load.specialLoadDetails,`Load ${loadId} special-load detail`)}:{}),dangerousGoodsClasses:uniqueIds(load.dangerousGoodsClasses,`Load ${loadId} dangerous-goods class`)} as SolverLoad});
 for(const load of loads){const compatible=positions.filter(position=>position.loadType===load.loadType&&load.weightKg<=position.maximumWeightKg&&(load.loadType==="BULK"||position.acceptedUldCodes.includes(load.uldCode!))&&(load.loadType!=="BULK"||load.volumeLitres===null||position.maximumVolumeLitres===null||load.volumeLitres<=position.maximumVolumeLitres));if(!compatible.length)throw new LoadPlanningProblemInvalid(`Load ${load.id} has no compatible loading position.`);if(load.lockedPositionId&&!compatible.some(position=>position.id===load.lockedPositionId))throw new LoadPlanningProblemInvalid(`Load ${load.id} cannot use its locked position ${load.lockedPositionId}.`)}
 const incompatiblePairs=(row.incompatiblePairs??[]).map((pair,index)=>{const left=id(pair.left,`Incompatibility ${index+1} first value`).toUpperCase(),right=id(pair.right,`Incompatibility ${index+1} second value`).toUpperCase();if(left===right)throw new LoadPlanningProblemInvalid(`Incompatibility ${index+1} must contain two different values.`);return{left,right,reason:id(pair.reason,`Incompatibility ${index+1} reason`)}});
 const specialLoadLimits=(row.specialLoadLimits??[]).map((limit,index)=>({code:id(limit.code,`Special-load limit ${index+1} code`).toUpperCase(),holdId:id(limit.holdId,`Special-load limit ${index+1} hold`),locationRef:optionalId(limit.locationRef,`Special-load limit ${index+1} location`),maximumQuantity:whole(limit.maximumQuantity,`Special-load limit ${index+1} maximum quantity`)}));
 for(const load of loads){const tokens=loadTokens(load);for(const pair of incompatiblePairs)if(tokens.has(pair.left)&&tokens.has(pair.right))throw new LoadPlanningProblemInvalid(`${load.description} contains incompatible loads (${pair.reason}). Split or correct the entry before AUTOLOAD.`)}
 const idealTrimIndexScaled=row.idealTrimIndexScaled===null?null:whole(Math.abs(row.idealTrimIndexScaled),"Ideal Trim index scale")*(row.idealTrimIndexScaled<0?-1:1);
 return{version:1,timeLimitSeconds:whole(row.timeLimitSeconds,"AUTOLOAD time limit",1),idealTrimIndexScaled,loads,positions,incompatiblePairs,specialLoadLimits};
}

export function validateLoadPlanningSolution(problem:LoadPlanningProblem,solution:LoadPlanningSolution):LoadPlanningSolution{
 if(!["OPTIMAL","FEASIBLE","INFEASIBLE","UNKNOWN"].includes(solution.status))throw new LoadPlanningProblemInvalid("The solver returned an unknown status.");
 if(solution.status==="INFEASIBLE"||solution.status==="UNKNOWN")return{...solution,assignments:[]};
 const assigned=new Map<string,string>(),positions=new Map(problem.positions.map(position=>[position.id,position])),occupied=new Set<string>(),bulkWeights=new Map<string,number>(),bulkVolumes=new Map<string,number>();
 for(const assignment of solution.assignments){if(assigned.has(assignment.loadId))throw new LoadPlanningProblemInvalid(`The solver assigned load ${assignment.loadId} more than once.`);const load=problem.loads.find(value=>value.id===assignment.loadId),position=positions.get(assignment.positionId);if(!load||!position)throw new LoadPlanningProblemInvalid("The solver returned an unknown load or position.");if(assignment.loadReference!==undefined&&assignment.loadReference!==null&&!/^[A-Z0-9-]{3,15}$/.test(assignment.loadReference))throw new LoadPlanningProblemInvalid(`Enter a valid ULD number for ${load.description.split(" · ")[0]}.`);if(load.loadType!==position.loadType||load.weightKg>position.maximumWeightKg||load.uldCode&&!position.acceptedUldCodes.includes(load.uldCode))throw new LoadPlanningProblemInvalid(`The solver assigned load ${load.id} to an incompatible position.`);if(load.lockedPositionId&&load.lockedPositionId!==position.id)throw new LoadPlanningProblemInvalid(`The solver moved locked load ${load.id}.`);if(position.loadType==="ULD"){for(const bay of position.occupiedBayIds){if(occupied.has(bay))throw new LoadPlanningProblemInvalid(`The solver produced an overlapping assignment at bay ${bay}.`);occupied.add(bay)}}else{const total=(bulkWeights.get(position.id)??0)+load.weightKg;if(total>position.maximumWeightKg)throw new LoadPlanningProblemInvalid(`The solver exceeded the Bulk weight limit at ${position.id}.`);bulkWeights.set(position.id,total);if(load.volumeLitres!==null&&position.maximumVolumeLitres!==null){const volume=(bulkVolumes.get(position.id)??0)+load.volumeLitres;if(volume>position.maximumVolumeLitres)throw new LoadPlanningProblemInvalid(`The solver exceeded the Bulk volume limit at ${position.id}.`);bulkVolumes.set(position.id,volume)}}assigned.set(load.id,position.id)}
 if(assigned.size!==problem.loads.length)throw new LoadPlanningProblemInvalid("The solver did not assign every released load.");
 for(let leftIndex=0;leftIndex<problem.loads.length;leftIndex++)for(let rightIndex=leftIndex+1;rightIndex<problem.loads.length;rightIndex++){const left=problem.loads[leftIndex],right=problem.loads[rightIndex],leftTokens=loadTokens(left),rightTokens=loadTokens(right),conflict=problem.incompatiblePairs.find(pair=>leftTokens.has(pair.left)&&rightTokens.has(pair.right)||leftTokens.has(pair.right)&&rightTokens.has(pair.left));if(conflict&&positions.get(assigned.get(left.id)!)?.segregationGroup===positions.get(assigned.get(right.id)!)?.segregationGroup)throw new LoadPlanningProblemInvalid(`The solver placed incompatible loads ${left.id} and ${right.id} in the same cargo compartment.`)}
 for(const limit of problem.specialLoadLimits){const count=problem.loads.filter(load=>load.specialLoadCodes.includes(limit.code)&&(()=>{const position=positions.get(assigned.get(load.id)!);return position?.holdId===limit.holdId&&(!limit.locationRef||(position.compartmentRef??position.locationRef)===limit.locationRef)})()).length;if(count>limit.maximumQuantity)throw new LoadPlanningProblemInvalid(`The solver exceeded the ${limit.code} quantity limit in ${limit.locationRef??limit.holdId}.`)}
 return solution;
}
