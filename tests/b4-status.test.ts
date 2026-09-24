import test from"node:test";import assert from"node:assert/strict";
import{b4Statuses}from"../src/domain/b4-status";
import{defaultPlanningRecord,newBaggageRecord,type BaggageRecord,type BaggageSnapshot}from"../src/domain/baggage-weights";

const defaults:BaggageRecord={id:"ZZ",baseline:false,values:{...newBaggageRecord("defaults").values,method:"STANDARD",male:"15",female:"15",child:"10",all:"15"}};
const baseline:BaggageRecord={id:"base",baseline:true,values:{...newBaggageRecord("weights").values,pieceMethod:"INHERIT",passengerMethod:"STANDARD",passenger:"15"}};
const base:BaggageSnapshot={canView:true,canEdit:true,revision:"r",unit:"KG",volumeUnit:"m3",operationMode:"STANDARD",defaultPerPiece:true,checkedBaggageDensity:"176",classes:[],variations:[],standardVariations:[],defaults,weights:[baseline],planning:[]};

test("B4 Standard operations require All Other Flights, variations and planning",()=>{
 const planning={...defaultPlanningRecord(base),id:"plan"};
 assert.deepEqual(b4Statuses({...base,planning:[planning]}),{defaults:"configured",passenger:"configured",planning:"configured",page:"configured"});
 assert.equal(b4Statuses({...base,weights:[],planning:[planning]}).page,"partial");
});
test("B4 Actual operations require planning assumptions only",()=>{
 const actual={...base,operationMode:"ACTUAL" as const,defaults:null,weights:[]};
 assert.deepEqual(b4Statuses(actual),{defaults:"skipped",passenger:"skipped",planning:"incomplete",page:"incomplete"});
 assert.equal(b4Statuses({...actual,planning:[{...defaultPlanningRecord(base),id:"plan"}]}).page,"configured");
});
test("B4 planning defaults to one bag and the Standard All-Passengers weight",()=>{
 const row=defaultPlanningRecord(base);assert.equal(row.values.bags,"1");assert.equal(row.values.weight,"15");assert.equal(row.values.volume,"");
});
test("B4 blank average volume requires the B1 checked-baggage density fallback",()=>{
 const planning={...defaultPlanningRecord(base),id:"plan"};
 assert.equal(b4Statuses({...base,planning:[planning],checkedBaggageDensity:""}).planning,"partial");
 assert.equal(b4Statuses({...base,planning:[planning]}).planning,"configured");
});
test("B3 variations require a B4-specific record or an explicit Standard decision",()=>{
 const variation={code:"CTR",description:"Charter"},planning={...defaultPlanningRecord(base),id:"plan"};
 const active={...base,defaultPerPiece:false,variations:[variation],planning:[planning]};
 assert.equal(b4Statuses(active).passenger,"partial");
 assert.equal(b4Statuses({...active,standardVariations:["CTR"]}).passenger,"configured");
 const charter={...baseline,id:"ctr",baseline:false,values:{...baseline.values,variation:"CTR"}};
 assert.equal(b4Statuses({...active,weights:[baseline,charter]}).passenger,"configured");
});
