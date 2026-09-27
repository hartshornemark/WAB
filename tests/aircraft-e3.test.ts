import test from"node:test";import assert from"node:assert/strict";
import{aircraftE3Status,e3ServiceStatus,e3WaterStatus}from"@/domain/aircraft-e3-status";
import{validateE3Service,validateE3Water,type AircraftE3Snapshot}from"@/domain/aircraft-e3";

const base:AircraftE3Snapshot={canView:true,canEdit:true,revision:"x",typeCode:"319",subtype:"100",applicabilityReviewed:false,waterAvailable:true,waterActive:false,serviceActive:false,waterRows:[],serviceRows:[],waterLocations:[{id:"XPW",name:"Potable Water",indexPerWeightUnit:.0108}]};

test("E3 remains incomplete until applicability is reviewed",()=>{assert.equal(e3WaterStatus(base),"skipped");assert.equal(e3ServiceStatus(base),"skipped");assert.equal(aircraftE3Status(base),"incomplete")});
test("E3 is configured when both sections are deliberately unchecked",()=>assert.equal(aircraftE3Status({...base,applicabilityReviewed:true}),"configured"));
test("an active E3 section requires a complete row immediately",()=>{const active={...base,waterActive:true};assert.equal(e3WaterStatus(active),"incomplete");assert.equal(aircraftE3Status(active),"incomplete")});
test("potable water index is calculated from D6 tank data",()=>{const rows=validateE3Water([{code:"A",tankId:"XPW",weight:100,remarks:"Standard"}],base.waterLocations);assert.equal(rows[0].index,1.08);assert.equal(e3WaterStatus({...base,waterActive:true,waterRows:rows}),"configured")});
test("potable water rejects a tank that is not defined in D6",()=>assert.throws(()=>validateE3Water([{code:"A",tankId:"BAD",weight:100}],base.waterLocations)));
test("service adjustments require a signed non-zero whole weight",()=>assert.throws(()=>validateE3Service([{code:"C",description:"Catering",weight:0,balanceArm:18,index:.2}])));
test("a complete service adjustment configures its section",()=>{const rows=validateE3Service([{code:"C",description:"Catering",weight:-50,balanceArm:18.037,index:-.2,remarks:"Remove catering"}]);assert.equal(e3ServiceStatus({...base,serviceActive:true,serviceRows:rows}),"configured")});
test("a service adjustment remains complete when its optional balance arm is blank",()=>{const rows=validateE3Service([{code:"F",description:"Flight Spares Kit",weight:150,balanceArm:null,index:0,remarks:null}]);assert.equal(rows[0].balanceArm,null);assert.equal(e3ServiceStatus({...base,serviceActive:true,serviceRows:rows}),"configured")});

test("service entry accepts signed text weights and decimal indexes",()=>{
 const [r]=validateE3Service([{code:"REM",description:"Remove item",weight:"-50",balanceArm:"18.037",index:"-0.25"}]);
 assert.equal(r.weight,-50);assert.equal(r.index,-.25);assert.equal(r.balanceArm,18.037);
 for(const index of ["-",".","",null])assert.throws(()=>validateE3Service([{code:"REM",description:"Remove item",weight:"-50",index}]));
});
