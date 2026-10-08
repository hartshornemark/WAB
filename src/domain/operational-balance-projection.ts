import type{AircraftC4Values}from"@/domain/aircraft-c4";
import{macPercentForIndex}from"@/domain/aircraft-balance-formula";
import type{EnvelopeBoundary}from"@/domain/aircraft-c5";
import type{LoadPlanningAssignment,LoadPlanningProblem}from"@/domain/load-planning-solver";

export type OperationalBalancePoint={weight:number;indexValue:number;macValue:number};
export type OperationalFuelCurvePoint={fuelWeight:number;indexValue:number};
export type OperationalRagTone="neutral"|"green"|"amber";
const boundaryIndex=(points:EnvelopeBoundary["fwd"],weight:number)=>{const rows=[...points].sort((a,b)=>a.weight-b.weight);if(rows.length<2||weight<rows[0].weight||weight>(rows.at(-1)?.weight??0))return null;const exact=rows.find(row=>row.weight===weight);if(exact)return exact.indexValue;const upperIndex=rows.findIndex(row=>row.weight>weight),lower=rows[upperIndex-1],upper=rows[upperIndex];return lower.indexValue+(upper.indexValue-lower.indexValue)*(weight-lower.weight)/(upper.weight-lower.weight)};

export function operationalZfwRag(point:OperationalBalancePoint|null,boundaries:EnvelopeBoundary|EnvelopeBoundary[],amberFraction=.04):{tone:OperationalRagTone;limit:"F"|"A"|null}{
 if(!point)return{tone:"neutral",limit:null};
 const margins=(Array.isArray(boundaries)?boundaries:[boundaries]).map(boundary=>{const fwd=boundaryIndex(boundary.fwd,point.weight),aft=boundaryIndex(boundary.aft,point.weight);if(fwd===null||aft===null)return null;const forward=Math.min(fwd,aft),rear=Math.max(fwd,aft);if(point.indexValue<forward||point.indexValue>rear||rear<=forward)return null;const width=rear-forward,fwdIsLow=fwd<=aft,fwdMargin=(point.indexValue-forward)/width,aftMargin=(rear-point.indexValue)/width;return fwdMargin<=aftMargin?{fraction:fwdMargin,limit:fwdIsLow?"F" as const:"A" as const}:{fraction:aftMargin,limit:fwdIsLow?"A" as const:"F" as const};});
 if(!margins.length||margins.some(margin=>margin===null))return{tone:"neutral",limit:null};
 const closest=margins.filter((margin):margin is NonNullable<typeof margin>=>margin!==null).sort((a,b)=>a.fraction-b.fraction)[0];
 return closest.fraction<amberFraction?{tone:"amber",limit:closest.limit}:{tone:"green",limit:null};
}

export function estimatedZfwBalancePoint(input:{weight:number;baseIndex:number;problem:LoadPlanningProblem;assignments:LoadPlanningAssignment[];formula:AircraftC4Values}):OperationalBalancePoint{
 const loads=new Map(input.problem.loads.map(load=>[load.id,load])),positions=new Map(input.problem.positions.map(position=>[position.id,position]));
 const freightIndex=input.assignments.reduce((total,assignment)=>{const load=loads.get(assignment.loadId),position=positions.get(assignment.positionId);return load&&position?total+load.weightKg*position.indexPerKgScaled/100_000:total},0),indexValue=input.baseIndex+freightIndex;
 return{weight:input.weight,indexValue,macValue:macPercentForIndex(input.weight,indexValue,input.formula)};
}

export function projectedFuelCurve(origin:OperationalBalancePoint,rows:OperationalFuelCurvePoint[],maximumWeight:number):Array<{weight:number;indexValue:number}>{
 const maximumFuel=Math.max(0,maximumWeight-origin.weight),sorted=[...rows].filter(row=>Number.isFinite(row.fuelWeight)&&Number.isFinite(row.indexValue)&&row.fuelWeight>=0).sort((a,b)=>a.fuelWeight-b.fuelWeight),usable=sorted.filter(row=>row.fuelWeight<=maximumFuel);
 if(!usable.some(row=>row.fuelWeight===0))usable.unshift({fuelWeight:0,indexValue:0});
 const lower=sorted.filter(row=>row.fuelWeight<maximumFuel).at(-1),upper=sorted.find(row=>row.fuelWeight>maximumFuel);
 if(maximumFuel>0&&lower&&upper&&!usable.some(row=>row.fuelWeight===maximumFuel)){const fraction=(maximumFuel-lower.fuelWeight)/(upper.fuelWeight-lower.fuelWeight);usable.push({fuelWeight:maximumFuel,indexValue:lower.indexValue+(upper.indexValue-lower.indexValue)*fraction})}
 return usable.map(row=>({weight:origin.weight+row.fuelWeight,indexValue:origin.indexValue+row.indexValue}));
}
