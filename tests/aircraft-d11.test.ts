import test from "node:test";
import assert from "node:assert/strict";
import { aircraftD11Status, d11FloorStatus } from "@/domain/aircraft-d11-status";
import { validateD11FloorLimits, type AircraftD11Snapshot } from "@/domain/aircraft-d11";

const base:AircraftD11Snapshot={
  canView:true,
  canEdit:true,
  revision:"r",
  typeCode:"319",
  subtype:"100",
  combinedActive:false,
  floorActive:false,
  asymmetricalActive:false,
  floorLimits:[
    {holdId:"1",holdType:"BLK",deckName:"Lower Deck",floorLoadingLimit:null},
    {holdId:"4",holdType:"BLK",deckName:"Lower Deck",floorLoadingLimit:null},
  ],
};

test("D11 is configured when no supported section is selected",()=>{
  assert.equal(d11FloorStatus(base),"not_active");
  assert.equal(aircraftD11Status(base),"configured");
});

test("selected Floor Loading Limits requires every D2 hold",()=>{
  assert.equal(aircraftD11Status({...base,floorActive:true}),"incomplete");
});

test("selected Floor Loading Limits is partial when only some holds are complete",()=>{
  assert.equal(aircraftD11Status({...base,floorActive:true,floorLimits:[{...base.floorLimits[0],floorLoadingLimit:500},base.floorLimits[1]]}),"partial");
});

test("selected Floor Loading Limits is configured when every hold has a positive limit",()=>{
  assert.equal(aircraftD11Status({...base,floorActive:true,floorLimits:base.floorLimits.map(row=>({...row,floorLoadingLimit:500}))}),"configured");
});

test("D11 validation rejects missing and non-positive limits",()=>{
  assert.throws(()=>validateD11FloorLimits([{holdId:"1",floorLoadingLimit:500}],base.floorLimits));
  assert.throws(()=>validateD11FloorLimits([{holdId:"1",floorLoadingLimit:0},{holdId:"4",floorLoadingLimit:500}],base.floorLimits));
});
