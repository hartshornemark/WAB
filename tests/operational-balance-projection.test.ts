import test from"node:test";import assert from"node:assert/strict";
import{estimatedZfwBalancePoint,projectedFuelCurve}from"@/domain/operational-balance-projection";

const formula={datum:0,referenceArm:0,constantK:0,constantC:1000,macRcLength:10,lemacLerc:0};
const problem={loads:[{id:"A",weightKg:900},{id:"B",weightKg:800}],positions:[{id:"P1",indexPerKgScaled:100},{id:"P2",indexPerKgScaled:200}]}as never;

test("plots eZFW from the operating index and solved freight distribution",()=>{const point=estimatedZfwBalancePoint({weight:47700,baseIndex:43,problem,assignments:[{loadId:"A",positionId:"P1"},{loadId:"B",positionId:"P2"}],formula});assert.equal(point.indexValue,45.5);assert.equal(point.weight,47700);assert.ok(Math.abs(point.macValue-9.5388)<.001)});
test("attaches and clips the configured fuel curve at MTOW",()=>{const origin={weight:47700,indexValue:45.5,macValue:9.5},points=projectedFuelCurve(origin,[{fuelWeight:0,indexValue:0},{fuelWeight:10000,indexValue:4},{fuelWeight:20000,indexValue:10}],62700);assert.deepEqual(points,[{weight:47700,indexValue:45.5},{weight:57700,indexValue:49.5},{weight:62700,indexValue:52.5}])});
