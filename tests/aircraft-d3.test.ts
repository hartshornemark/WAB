import test from"node:test";
import assert from"node:assert/strict";
import{AircraftD3Invalid,validateAircraftD3Configuration,type AircraftD3Configuration,type AircraftD3Position,type AircraftD3Snapshot}from"../src/domain/aircraft-d3";
import{aircraftD3ConfigurationStatus,aircraftD3Status}from"../src/domain/aircraft-d3-status";

const uldTypes=["LD3-45"];
const row:AircraftD3Position={rowType:"POSITION",positionId:"11P",compartmentId:"1",uldType:"LD3-45",uldBaseCode:"K",groupId:"G1",maxWeight:1500,volume:null,lateralCentroid:null,lateralFrom:null,lateralTo:null,balanceCentroid:12.5,balanceFrom:12,balanceTo:13,indexPerWeightUnit:.001,colour:"#12AbEF"};
const config:AircraftD3Configuration={holdId:"1",code:"MAIN",description:null,expectedPositionCount:1,rows:[row]};
const snap=(v:Partial<AircraftD3Snapshot>={}):AircraftD3Snapshot=>({canView:true,canEdit:true,revision:"r",typeCode:"330",subtype:"300",uldHolds:[{id:"1",compartments:["1"]}],uldTypes,configurations:[config],...v});
const validate=(value:unknown,formula:null|{referenceArm:number;constantC:number}=null)=>validateAircraftD3Configuration(value,[{id:"1"}],formula,uldTypes);

test("D3 is skipped when D2 has no ULD holds",()=>assert.equal(aircraftD3Status(snap({uldHolds:[],configurations:[]})),"skipped"));
test("D3 is incomplete before any configuration is added",()=>assert.equal(aircraftD3Status(snap({configurations:[]})),"incomplete"));
test("D3 requires a configuration for every ULD hold",()=>assert.equal(aircraftD3Status(snap({uldHolds:[{id:"1",compartments:["1"]},{id:"2",compartments:["2"]}]})),"partial"));
test("a configuration is complete only at its declared physical position count",()=>{assert.equal(aircraftD3ConfigurationStatus(config),"configured");assert.equal(aircraftD3ConfigurationStatus({...config,expectedPositionCount:2}),"partial")});
test("group-limit rows do not count as physical positions",()=>assert.equal(aircraftD3ConfigurationStatus({...config,expectedPositionCount:2,rows:[row,{...row,rowType:"GROUP_LIMIT",positionId:"G1",compartmentId:null,uldType:null}]}),"partial"));
test("validates position IDs, ULD Types and HEX colours",()=>{assert.doesNotThrow(()=>validate(config));assert.throws(()=>validate({...config,rows:[{...row,positionId:"LONG"}]}),AircraftD3Invalid);assert.throws(()=>validate({...config,rows:[{...row,compartmentId:null}]}),/Compartment/);assert.throws(()=>validate({...config,rows:[{...row,uldType:null}]}),/ULD Type/);assert.throws(()=>validate({...config,rows:[{...row,uldType:"LD3"}]}),/ULD Type/);assert.throws(()=>validate({...config,rows:[{...row,colour:"red"}]}),/HEX/) });
test("accepts blank optional values and a signed decimal Index Per Weight Unit",()=>{const validated=validate({...config,rows:[{...row,volume:null,indexPerWeightUnit:-0.00972,lateralFrom:null,lateralCentroid:null,lateralTo:null,balanceFrom:null,balanceTo:null}]});assert.equal(validated.rows[0].volume,null);assert.equal(validated.rows[0].indexPerWeightUnit,-0.00972)});
test("derives the Balance Arm Centroid from C4 and Index Per Weight Unit",()=>{const validated=validate({...config,rows:[{...row,balanceCentroid:99,balanceFrom:null,balanceTo:null,indexPerWeightUnit:-0.00972}]},{referenceArm:18.85,constantC:838.7});assert.equal(validated.rows[0].balanceCentroid,10.697836)});
