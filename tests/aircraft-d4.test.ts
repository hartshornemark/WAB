import test from"node:test";import assert from"node:assert/strict";import{AircraftD4Invalid,validateAircraftD4Doors,type AircraftD4Door}from"../src/domain/aircraft-d4";import{aircraftD4DoorsStatus,aircraftD4Status}from"../src/domain/aircraft-d4-status";
const row:AircraftD4Door={holdId:"1",holdType:"BLK",deckName:"Lower Deck",forwardArm:9.791,aftArm:11.608,height:1.228,orientation:"R"};
test("D4 is configured when every hold has a complete door",()=>assert.equal(aircraftD4DoorsStatus([row]),"configured"));
test("D4 remains configured when door height is unavailable",()=>assert.equal(aircraftD4DoorsStatus([{...row,height:null}]),"configured"));
test("D4 is partial when only some holds have required door data",()=>assert.equal(aircraftD4DoorsStatus([row,{...row,holdId:"2",orientation:null}]),"partial"));
test("D4 is incomplete without holds",()=>assert.equal(aircraftD4DoorsStatus([]),"incomplete"));
test("D4 is optional when Doors are not selected",()=>assert.equal(aircraftD4Status({canView:true,canEdit:true,revision:"r",typeCode:"320",subtype:"200",doorsActive:false,locksActive:false,missingRestraintsActive:false,doors:[row]}),"optional"));
test("D4 applies door completion rules when Doors are selected",()=>assert.equal(aircraftD4Status({canView:true,canEdit:true,revision:"r",typeCode:"320",subtype:"200",doorsActive:true,locksActive:false,missingRestraintsActive:false,doors:[row]}),"configured"));
test("D4 rejects reversed door arms",()=>assert.throws(()=>validateAircraftD4Doors([{...row,forwardArm:12}], [row]),AircraftD4Invalid));
test("D4 restricts orientation to L R or C",()=>assert.throws(()=>validateAircraftD4Doors([{...row,orientation:"X"}], [row]),AircraftD4Invalid));
test("D4 accepts a missing optional door height",()=>assert.equal(validateAircraftD4Doors([{...row,height:null}],[row])[0]?.height,null));
test("D4 rejects a non-positive supplied door height",()=>assert.throws(()=>validateAircraftD4Doors([{...row,height:0}],[row]),AircraftD4Invalid));

test("D4 saves unknown doors as blank alongside known doors without reducing completion of known doors",()=>{
 const unknown={...row,holdId:"MDECK:MDA",forwardArm:null,aftArm:null,height:null,orientation:null};
 const saved=validateAircraftD4Doors([row,unknown],[row,unknown]);
 assert.deepEqual(saved[1],unknown);
 assert.equal(aircraftD4DoorsStatus(saved),"configured");
 assert.equal(aircraftD4DoorsStatus([unknown]),"incomplete");
 assert.throws(()=>validateAircraftD4Doors([row,{...unknown,forwardArm:9}],[row,unknown]),AircraftD4Invalid);
});
