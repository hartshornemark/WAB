import test from"node:test";
import assert from"node:assert/strict";
import{effectiveAircraftD3Snapshot,sortAircraftD3Snapshot,AircraftD3Invalid,blockedAircraftD3PositionIds,validateAircraftD3Configuration,type AircraftD3Configuration,type AircraftD3Position,type AircraftD3Snapshot,type AircraftD3UldOption}from"../src/domain/aircraft-d3";
import{aircraftD3ConfigurationStatus,aircraftD3Status}from"../src/domain/aircraft-d3-status";

const uldTypes=["LD3-45"];
const uldOptions:AircraftD3UldOption[]=[{code:"AKE",type:"LD3-45",baseCode:"K",baseWidth:61.5,baseLength:60.4,adopted:true},{code:"AVE",type:"LD3-45",baseCode:"K",baseWidth:61.5,baseLength:60.4,adopted:true}];
const atomicBay={id:"11L",compartmentId:"1",lateralCentroid:null,lateralFrom:null,lateralTo:null,balanceCentroid:12.5,balanceFrom:12,balanceTo:13,colour:null};
const row:AircraftD3Position={rowType:"POSITION",positionId:"11P",compartmentId:"1",uldCode:"AKE",uldType:"LD3-45",uldBaseCode:"K",groupId:"G1",occupiedBayIds:["11L"],maxWeight:1500,volume:null,lateralCentroid:null,lateralFrom:null,lateralTo:null,balanceCentroid:12.5,balanceFrom:12,balanceTo:13,indexPerWeightUnit:.001,colour:"#12AbEF"};
const config:AircraftD3Configuration={holdId:"1",code:"MAIN",description:null,expectedPositionCount:1,atomicBays:[atomicBay],rows:[row]};
const snap=(v:Partial<AircraftD3Snapshot>={}):AircraftD3Snapshot=>({canView:true,canEdit:true,revision:"r",typeCode:"330",subtype:"300",uldHolds:[{id:"1",compartments:["1"]}],uldTypes,uldOptions,configurations:[config],...v});
const validate=(value:unknown,formula:null|{referenceArm:number;constantC:number}=null)=>validateAircraftD3Configuration(value,[{id:"1"}],formula,uldOptions);

test("D3 is skipped when D2 has no ULD holds",()=>assert.equal(aircraftD3Status(snap({uldHolds:[],configurations:[]})),"skipped"));
test("D3 is incomplete before any configuration is added",()=>assert.equal(aircraftD3Status(snap({configurations:[]})),"incomplete"));
test("D3 requires a configuration for every ULD hold",()=>assert.equal(aircraftD3Status(snap({uldHolds:[{id:"1",compartments:["1"]},{id:"2",compartments:["2"]}]})),"partial"));
test("a configuration is complete only at its declared atomic bay count",()=>{assert.equal(aircraftD3ConfigurationStatus(config),"configured");assert.equal(aircraftD3ConfigurationStatus({...config,expectedPositionCount:2}),"partial")});
test("group-limit rows do not count as atomic bays",()=>assert.equal(aircraftD3ConfigurationStatus({...config,expectedPositionCount:2,rows:[row,{...row,rowType:"GROUP_LIMIT",positionId:"G1",compartmentId:null,uldCode:null,uldType:null,occupiedBayIds:[]}]}),"partial"));
test("validates position IDs, ULD Codes and HEX colours",()=>{assert.doesNotThrow(()=>validate(config));assert.throws(()=>validate({...config,rows:[{...row,positionId:"TOO-LONG"}]}),AircraftD3Invalid);assert.throws(()=>validate({...config,rows:[{...row,compartmentId:null}]}),/Compartment/);assert.throws(()=>validate({...config,rows:[{...row,uldCode:null}]}),/ULD Code/);assert.throws(()=>validate({...config,rows:[{...row,uldCode:"PKC"}]}),/ULD Code/);assert.throws(()=>validate({...config,rows:[{...row,colour:"red"}]}),/HEX/) });
test("combined positions occupy multiple atomic bays and reject unknown bays",()=>{const combined={...config,expectedPositionCount:2,atomicBays:[atomicBay,{...atomicBay,id:"11R"}],rows:[{...row,occupiedBayIds:["11L","11R"]}]};assert.deepEqual(validate(combined).rows[0].occupiedBayIds,["11L","11R"]);assert.throws(()=>validate({...combined,rows:[{...row,occupiedBayIds:["12L"]}]}),/does not exist/)});
test("the same display position may use different ULD codes and lock geometry",()=>{const validated=validateAircraftD3Configuration({...config,rows:[row,{...row,uldCode:"AVE",balanceCentroid:12.6,balanceFrom:12.1,balanceTo:13.1}]},[{id:"1"}],null,uldOptions);assert.equal(validated.rows.length,2);assert.deepEqual(validated.rows.map(item=>item.uldCode),["AKE","AVE"])});
test("a combined pallet position blocks every arrangement sharing an atomic bay",()=>{const ids=["11L","11R","12L","12R"],bays=ids.map(id=>({...atomicBay,id})),arrangement=(positionId:string,occupiedBayIds:string[]):AircraftD3Position=>({...row,positionId,occupiedBayIds});const model={...config,expectedPositionCount:4,atomicBays:bays,rows:[arrangement("11L",["11L"]),arrangement("11R",["11R"]),arrangement("11",["11L","11R"]),arrangement("12L",["12L"]),arrangement("12R",["12R"]),arrangement("12",["12L","12R"]),arrangement("11P",ids)]};assert.deepEqual(blockedAircraftD3PositionIds(model,"11P"),["11","11L","11R","12","12L","12R"])});
test("accepts blank optional values and a signed decimal Index Per Weight Unit",()=>{const validated=validate({...config,rows:[{...row,volume:null,indexPerWeightUnit:-0.00972,lateralFrom:null,lateralCentroid:null,lateralTo:null,balanceFrom:null,balanceTo:null}]});assert.equal(validated.rows[0].volume,null);assert.equal(validated.rows[0].indexPerWeightUnit,-0.00972)});
test("derives the Balance Arm Centroid from C4 and Index Per Weight Unit",()=>{const validated=validate({...config,rows:[{...row,balanceCentroid:99,balanceFrom:null,balanceTo:null,indexPerWeightUnit:-0.00972}]},{referenceArm:18.85,constantC:838.7});assert.equal(validated.rows[0].balanceCentroid,10.697836)});

test("import validation preserves CSV centroids instead of replacing them from C4",()=>{const validated=validateAircraftD3Configuration(config,[{id:"1"}],{referenceArm:20,constantC:1000},uldOptions,true);assert.equal(validated.rows[0].balanceCentroid,12.5)});

test("a fitted configuration filters atomic bays and their dependent loading positions",()=>{const secondBay={...atomicBay,id:"12L",configurationCodes:["0ACT"]};const secondRow={...row,positionId:"12P",occupiedBayIds:["12L"],configurationCodes:["0ACT"]};const model=snap({fuelConfigurations:[{code:"0ACT",description:"None"},{code:"2ACT",description:"Two"}],configurations:[{...config,expectedPositionCount:2,atomicBays:[atomicBay,secondBay],rows:[row,secondRow]}]});const effective=effectiveAircraftD3Snapshot(model,"2ACT");assert.deepEqual(effective.configurations[0].atomicBays.map(item=>item.id),["11L"]);assert.deepEqual(effective.configurations[0].rows.map(item=>item.positionId),["11P"]);assert.equal(effective.configurations[0].expectedPositionCount,1)});
test("position overrides replace only the selected fitted configuration values",()=>{const model=snap({fuelConfigurations:[{code:"2ACT",description:"Two"}],configurations:[{...config,rows:[{...row,configurationOverrides:[{configurationCode:"2ACT",maxWeight:1200,volume:9}]}]}]});const effective=effectiveAircraftD3Snapshot(model,"2ACT");assert.equal(effective.configurations[0].rows[0].maxWeight,1200);assert.equal(effective.configurations[0].rows[0].volume,9)});

test("hold lists and configurations use derived sorting arms without filling missing centroids",()=>{
 const input=snap({uldHolds:[{id:"AFT",balanceCentroid:null,sortBalanceArm:30},{id:"UNKNOWN",balanceCentroid:null},{id:"FWD",balanceCentroid:null,sortBalanceArm:13}],configurations:[{...config,holdId:"AFT"},{...config,holdId:"UNKNOWN"},{...config,holdId:"FWD"}]});
 const sorted=sortAircraftD3Snapshot(input);
 assert.deepEqual(sorted.uldHolds.map(h=>h.id),["FWD","AFT","UNKNOWN"]);
 assert.deepEqual(sorted.configurations.map(h=>h.holdId),["FWD","AFT","UNKNOWN"]);
 assert.equal(sorted.uldHolds[0].balanceCentroid,null);
 assert.equal(input.uldHolds[0].id,"AFT");
});
