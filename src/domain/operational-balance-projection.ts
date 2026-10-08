import type{AircraftC4Values}from"@/domain/aircraft-c4";
import{macPercentForIndex}from"@/domain/aircraft-balance-formula";
import type{LoadPlanningAssignment,LoadPlanningProblem}from"@/domain/load-planning-solver";

export type OperationalBalancePoint={weight:number;indexValue:number;macValue:number};
export type OperationalFuelCurvePoint={fuelWeight:number;indexValue:number};

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
