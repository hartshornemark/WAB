import test from "node:test";
import assert from "node:assert/strict";
import { A319_LAYOUT, A320_LAYOUT, buildHoldLayout, holdLayoutUnavailable, holdLayoutX } from "../src/domain/hold-layout";
import type { AircraftD2Snapshot, AircraftD2HoldRow } from "../src/domain/aircraft-d2";
import type { AircraftD4Snapshot } from "../src/domain/aircraft-d4";
import type { AircraftD3Snapshot } from "../src/domain/aircraft-d3";
const hold: AircraftD2HoldRow = { name:"5",holdType:"BLK",deckCode:"LOWER",maxWeight:1497,maxVolume:7.22,balanceCentroid:24.649,balanceFrom:24.028,balanceTo:27.270,indexPerWeightUnit:0.00840,lateralCentroid:null,lateralFrom:null,lateralTo:null,compartments:[] };
const d2 = (patch:Partial<AircraftD2Snapshot>={}):AircraftD2Snapshot => ({canView:true,canEdit:true,revision:"r",typeCode:"319",subtype:"100",bulkApplicable:true,uldApplicable:false,bulkBalanceLimitsRequired:true,uldBalanceLimitsRequired:true,rows:[hold],deckTypes:[{code:"LOWER",name:"Lower Deck"}],...patch});
const d4 = (patch:Partial<AircraftD4Snapshot>={}):AircraftD4Snapshot => ({canView:true,canEdit:true,revision:"r",typeCode:"319",subtype:"100",doors:[{holdId:"5",holdType:"BLK",deckName:"Lower Deck",forwardArm:25.287,aftArm:26.240,height:.773,orientation:"R"}],...patch});
test("D2 configured and D4 incomplete produces holds only",()=>{const layout=buildHoldLayout(d2(),d4({doors:[]}));assert.equal(layout.doorsIncluded,false);assert.equal(layout.doors.length,0);assert.equal(layout.holds.length,1)});
test("configured D4 adds current saved doors and correct datum positions",()=>{const layout=buildHoldLayout(d2(),d4());assert.equal(layout.doorsIncluded,true);assert.equal(layout.doors[0].x,holdLayoutX(26.240));assert.ok(Math.abs(layout.holds[0].width-(27.270-24.028)*A319_LAYOUT.span/A319_LAYOUT.length)<1e-8);assert.equal(holdLayoutX(A319_LAYOUT.noseArm),A319_LAYOUT.tailX)});
test("partial D4 never leaks doors missing required data into the diagram",()=>{const snap=d4();snap.doors[0].orientation=null;assert.deepEqual(buildHoldLayout(d2(),snap).doors,[])});
test("D4 must cover every applicable hold",()=>{const snap=d4();snap.doors[0].holdId="1";assert.equal(buildHoldLayout(d2(),snap).doorsIncluded,false)});
test("all checked bulk and ULD holds are drawn, separately grouped by deck",()=>{const snap=d2({uldApplicable:true,rows:[hold,{...hold,name:"A",holdType:"ULD",deckCode:"MAIN"}]});const layout=buildHoldLayout(snap,d4());assert.equal(layout.holds.length,2);assert.equal(layout.decks.length,2);assert.equal(layout.doorsIncluded,false)});
test("unchecked sections are excluded even if stale rows exist",()=>{const snap=d2({rows:[hold,{...hold,name:"A",holdType:"ULD"}]});assert.deepEqual(buildHoldLayout(snap,d4()).holds.map(h=>h.name),["5"])});
test("incomplete D2 cannot render a diagram",()=>assert.throws(()=>buildHoldLayout(d2({uldApplicable:null}),d4()),/Complete all applicable/));
test("D2 can be configured without limits but a diagram cannot invent them",()=>assert.match(holdLayoutUnavailable(d2({bulkBalanceLimitsRequired:false,rows:[{...hold,balanceFrom:null,balanceTo:null}]}))!,/From and To/));
test("unsupported aircraft calibration and denied view are blocked",()=>{assert.match(holdLayoutUnavailable(d2({typeCode:"320"}))!,/calibrated/);assert.match(holdLayoutUnavailable(d2({canView:false}))!,/permission/);assert.equal(buildHoldLayout(d2(),d4({canView:false})).doors.length,0)});
test("invalid door position reports the D4 error instead of substituting a location",()=>{const snap=d4();snap.doors[0].forwardArm=45.287;snap.doors[0].aftArm=46.240;assert.throws(()=>buildHoldLayout(d2(),snap),/Door 5/)});
test("new saved weights and door positions are used on subsequent builds",()=>{const snap=d4();snap.doors[0].forwardArm=25.4;const layout=buildHoldLayout(d2({rows:[{...hold,maxWeight:1600}]}),snap);assert.equal(layout.holds[0].maxWeight,1600);assert.equal(layout.doors[0].width,holdLayoutX(25.4)-holdLayoutX(26.240))});
test("A320-200 uses its own calibrated Airbus plan and datum",()=>{
  const a320Hold={...hold,name:"1",balanceCentroid:9.730,balanceFrom:7.255,balanceTo:12.205};
  const a320D2=d2({typeCode:"320",subtype:"200",rows:[a320Hold]});
  const a320D4=d4({typeCode:"320",subtype:"200",doors:[{...d4().doors[0],holdId:"1",forwardArm:7.255,aftArm:9.065}]});
  const layout=buildHoldLayout(a320D2,a320D4);
  assert.equal(layout.holds[0].x,holdLayoutX(12.205,A320_LAYOUT));
  assert.equal(layout.doors[0].width,holdLayoutX(7.255,A320_LAYOUT)-holdLayoutX(9.065,A320_LAYOUT));
});
test("A320 doors may provide access outside the associated D2 hold limits",()=>{
  const a320Hold={...hold,balanceCentroid:29.380,balanceFrom:27.548,balanceTo:31.212};
  const a320D2=d2({typeCode:"320",subtype:"200",rows:[a320Hold]});
  const a320D4=d4({typeCode:"320",subtype:"200",doors:[{...d4().doors[0],forwardArm:25.860,aftArm:26.720,height:.89}]});
  const layout=buildHoldLayout(a320D2,a320D4);
  assert.equal(layout.doorsIncluded,true);
  assert.equal(layout.doors.length,1);
  assert.equal(layout.holds[0].x,holdLayoutX(31.212-3.068,A320_LAYOUT));
  assert.equal(layout.doors[0].x,holdLayoutX(26.720,A320_LAYOUT));
});
test("bulk Areas divide their Hold by saved weight and retain their identifiers",()=>{
  const areaHold={...hold,compartments:[{id:"5",areas:[
    {id:"51",maxWeight:374,maxVolume:1.47,indexPerWeightUnit:.01},
    {id:"52",maxWeight:353,maxVolume:1.39,indexPerWeightUnit:.02},
    {id:"53",maxWeight:770,maxVolume:3.02,indexPerWeightUnit:.03},
  ]}]};
  const layout=buildHoldLayout(d2({rows:[areaHold]}),d4());
  assert.deepEqual(layout.holds[0].subdivisions.map(segment=>segment.id),["51","52","53"]);
  assert.ok(Math.abs(layout.holds[0].subdivisions.reduce((sum,segment)=>sum+segment.width,0)-layout.holds[0].width)<1e-8);
});
test("a Hold ID labels an undivided Hold",()=>{
  const layout=buildHoldLayout(d2(),d4());
  assert.deepEqual(layout.holds[0].subdivisions.map(segment=>[segment.kind,segment.id]),[["HOLD","5"]]);
});
test("Compartment IDs label a Hold when no Areas or Bays exist",()=>{
  const compartmentHold={...hold,compartments:[{id:"5A",areas:[]},{id:"5B",areas:[]}]};
  const layout=buildHoldLayout(d2({rows:[compartmentHold]}),d4());
  assert.deepEqual(layout.holds[0].subdivisions.map(segment=>[segment.kind,segment.id]),[["COMPARTMENT","5A"],["COMPARTMENT","5B"]]);
  assert.ok(layout.holds[0].subdivisions.every(segment=>segment.width===layout.holds[0].width/2));
});
test("configured D3 physical positions become Bay subdivisions ordered by centroid",()=>{
  const uldHold={...hold,name:"1",holdType:"ULD" as const,compartments:[{id:"1",areas:[]}]};
  const a320D2=d2({typeCode:"320",subtype:"200",bulkApplicable:false,uldApplicable:true,rows:[uldHold]});
  const d3:AircraftD3Snapshot={canView:true,canEdit:true,revision:"r",typeCode:"320",subtype:"200",uldHolds:[{id:"1",compartments:["1"]}],uldTypes:["LD3-45"],configurations:[{holdId:"1",code:"100",description:"DEFAULT",expectedPositionCount:2,rows:[
    {rowType:"POSITION",positionId:"11",compartmentId:"1",uldType:"LD3-45",uldBaseCode:"K",groupId:null,maxWeight:1134,volume:null,lateralCentroid:null,lateralFrom:null,lateralTo:null,balanceCentroid:10,balanceFrom:null,balanceTo:null,indexPerWeightUnit:.01,colour:null},
    {rowType:"POSITION",positionId:"12",compartmentId:"1",uldType:"LD3-45",uldBaseCode:"K",groupId:null,maxWeight:1134,volume:null,lateralCentroid:null,lateralFrom:null,lateralTo:null,balanceCentroid:11,balanceFrom:null,balanceTo:null,indexPerWeightUnit:.02,colour:null},
  ]}]};
  const layout=buildHoldLayout(a320D2,d4({typeCode:"320",subtype:"200",doors:[]}),d3);
  assert.deepEqual(layout.holds[0].subdivisions.map(segment=>segment.id),["12","11"]);
  assert.ok(layout.holds[0].subdivisions.every(segment=>segment.kind==="BAY"));
});
