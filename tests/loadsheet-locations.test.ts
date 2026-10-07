import assert from"node:assert/strict";
import test from"node:test";
import{aircraftLoadsheetLocations}from"@/domain/loadsheet-locations";
import type{AircraftD2Snapshot}from"@/domain/aircraft-d2";
import type{AircraftD3Snapshot}from"@/domain/aircraft-d3";

const base:Omit<AircraftD2Snapshot,"rows">={canView:true,canEdit:true,revision:"1",typeCode:"319",subtype:"100",bulkApplicable:true,uldApplicable:false,bulkBalanceLimitsRequired:false,uldBalanceLimitsRequired:false,deckTypes:[{code:"LOWER",name:"Lower Deck"}]};
const d3:AircraftD3Snapshot={canView:true,canEdit:true,revision:"1",typeCode:"319",subtype:"100",uldHolds:[],uldTypes:[],configurations:[]};
const hold={id:"LOWER:1",name:"1",holdType:"BLK"as const,deckCode:"LOWER",maxWeight:2268,maxVolume:8.56,lateralCentroid:null,lateralFrom:null,lateralTo:null,balanceCentroid:11.436,balanceFrom:9.858,balanceTo:13.107,indexPerWeightUnit:-.00581,compartments:[{id:"1",areas:[]}],configurationCodes:undefined,configurationOverrides:undefined};

test("a bulk hold without areas remains a simulator loading position",()=>{
 const d2:AircraftD2Snapshot={...base,rows:[hold]};
 assert.deepEqual(aircraftLoadsheetLocations(d2,d3),[{id:"BLK:LOWER:1",description:"1 (Complete bulk hold)",indexPerWeightUnit:-.00581,maximumWeight:2268,occupiedBayIds:[]}]);
});

test("configured bulk areas remain the selectable positions",()=>{
 const d2:AircraftD2Snapshot={...base,rows:[{...hold,compartments:[{id:"1",areas:[{id:"11",maxWeight:1000,maxVolume:null,indexPerWeightUnit:-.006,configurationCodes:undefined,configurationOverrides:undefined}]}]}]};
 assert.deepEqual(aircraftLoadsheetLocations(d2,d3),[{id:"BLK:LOWER:1:1:11",description:"1 / 1 / 11 (Bulk area)",indexPerWeightUnit:-.006,maximumWeight:1000,occupiedBayIds:[]}]);
});
