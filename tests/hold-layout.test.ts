import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { buildHoldLayout as build, holdLayoutMirrorsAircraftProfile, holdLayoutUnavailable as unavailable, holdLayoutX as position, separateUldPositionDisplayRanges } from "../src/domain/hold-layout";
import { A319_LAYOUT,A320_LAYOUT,aircraftLayoutFor } from "./fixtures/aircraft-layouts";
const buildHoldLayout=(d2:AircraftD2Snapshot,d4:AircraftD4Snapshot,d3?:AircraftD3Snapshot)=>build(d2,d4,d3,aircraftLayoutFor(d2.typeCode,d2.subtype)!);
const holdLayoutUnavailable=(d2:AircraftD2Snapshot)=>unavailable(d2,aircraftLayoutFor(d2.typeCode,d2.subtype));
const holdLayoutX=(arm:number,aircraft=A319_LAYOUT)=>position(arm,aircraft);
import { effectiveAircraftD2Snapshot, type AircraftD2Snapshot, type AircraftD2HoldRow } from "../src/domain/aircraft-d2";
import type { AircraftD4Snapshot } from "../src/domain/aircraft-d4";
import type { AircraftD3Snapshot } from "../src/domain/aircraft-d3";
const hold: AircraftD2HoldRow = { name:"5",holdType:"BLK",deckCode:"LOWER",maxWeight:1497,maxVolume:7.22,balanceCentroid:24.649,balanceFrom:24.028,balanceTo:27.270,indexPerWeightUnit:0.00840,lateralCentroid:null,lateralFrom:null,lateralTo:null,compartments:[] };
const d2 = (patch:Partial<AircraftD2Snapshot>={}):AircraftD2Snapshot => ({canView:true,canEdit:true,revision:"r",typeCode:"319",subtype:"100",bulkApplicable:true,uldApplicable:false,bulkBalanceLimitsRequired:true,uldBalanceLimitsRequired:true,rows:[hold],deckTypes:[{code:"LOWER",name:"Lower Deck"}],...patch});
const d4 = (patch:Partial<AircraftD4Snapshot>={}):AircraftD4Snapshot => ({canView:true,canEdit:true,revision:"r",typeCode:"319",subtype:"100",doorsActive:true,locksActive:false,missingRestraintsActive:false,doors:[{holdId:"5",holdType:"BLK",deckName:"Lower Deck",forwardArm:25.287,aftArm:26.240,height:.773,orientation:"R"}],...patch});
test("D2 configured and D4 incomplete produces holds only",()=>{const layout=buildHoldLayout(d2(),d4({doors:[]}));assert.equal(layout.doorsIncluded,false);assert.equal(layout.doors.length,0);assert.equal(layout.holds.length,1)});
test("aircraft hold overlays remain centred on their calibrated fuselage",()=>{
  assert.equal(A319_LAYOUT.holdY+A319_LAYOUT.holdHeight/2,A319_LAYOUT.centreY);
  assert.equal(A320_LAYOUT.holdY+A320_LAYOUT.holdHeight/2,A320_LAYOUT.centreY);
});
test("B767-300 hold profile is mirrored into the common tail-left, nose-right display",()=>{
  assert.equal(holdLayoutMirrorsAircraftProfile({typeCode:"763",subtype:"300"}),true);
  assert.equal(holdLayoutMirrorsAircraftProfile({typeCode:"319",subtype:"100"}),false);
});
test("aircraft vector assets and image frames require an explicit calibration review when changed",()=>{
  const assetHash=(name:string)=>createHash("sha256").update(readFileSync(join(process.cwd(),"src/assets/aircraft-layouts",name))).digest("hex");
  const assetVersion=(asset:string)=>new URL(asset,"http://layout.local").searchParams.get("v");
  // These vectors, their crops and the image frame form one coordinate system.
  // A changed hash is intentional friction: review the rendered overlay, then
  // update this contract together with the aircraft calibration.
  const a319Hash=assetHash("a319-100-fuselage.svg");
  const a320Hash=assetHash("a320-200-fuselage.svg");
  assert.equal(a319Hash,"1800f1d814208e34c17d7ad7a91cc4abdd7f18f8251ae91ad8ef6ab1e1cdb4d6");
  assert.equal(a320Hash,"f5de949b13d92da8bcf889a0644390edde83e33a1ed35146279e51b19e47e0f7");
  assert.equal(assetVersion(A319_LAYOUT.asset),a319Hash.slice(0,12));
  assert.equal(assetVersion(A320_LAYOUT.asset),a320Hash.slice(0,12));
  assert.deepEqual(A319_LAYOUT.imageFrame,{x:102,y:327.25,width:236,height:72});
  assert.deepEqual(A320_LAYOUT.imageFrame,{x:102,y:327.25,width:236,height:72});
  assert.deepEqual(
    [A319_LAYOUT.tailX,A319_LAYOUT.span,A319_LAYOUT.centreY,A319_LAYOUT.holdY,A319_LAYOUT.holdHeight],
    [330.3,192.9,363,352,22],
  );
});
test("configured D4 adds current saved doors and correct datum positions",()=>{const layout=buildHoldLayout(d2(),d4());assert.equal(layout.doorsIncluded,true);assert.equal(layout.doors[0].x,holdLayoutX(26.240));assert.ok(Math.abs(layout.holds[0].width-(27.270-24.028)*A319_LAYOUT.span/A319_LAYOUT.length)<1e-8);assert.equal(holdLayoutX(A319_LAYOUT.noseArm),A319_LAYOUT.tailX)});
test("B767-300 station calibration follows both reviewed cargo-door anchors",()=>{
  const aircraft={...A319_LAYOUT,typeCode:"763",subtype:"300",length:2163,noseArm:92.5,stationOriginX:1939.213513,span:2053.154428};
  assert.ok(Math.abs(position(361,aircraft)-1596.5465)<.001);
  assert.ok(Math.abs(position(1470.2,aircraft)-543.676)<.001);
  assert.ok(position(300.7,aircraft)>1596.5465&&position(425.5,aircraft)<1596.5465);
});
test("partial D4 never leaks doors missing required data into the diagram",()=>{const snap=d4();snap.doors[0].orientation=null;assert.deepEqual(buildHoldLayout(d2(),snap).doors,[])});
test("D4 must cover every applicable hold",()=>{const snap=d4();snap.doors[0].holdId="1";assert.equal(buildHoldLayout(d2(),snap).doorsIncluded,false)});
test("all checked bulk and ULD holds are drawn, separately grouped by deck",()=>{const snap=d2({uldApplicable:true,rows:[hold,{...hold,name:"FWD",holdType:"ULD",deckCode:"MAIN",maxVolume:null}]});const layout=buildHoldLayout(snap,d4());assert.equal(layout.holds.length,2);assert.equal(layout.decks.length,2);assert.equal(layout.doorsIncluded,false)});
test("unchecked sections are excluded even if stale rows exist",()=>{const snap=d2({rows:[hold,{...hold,name:"A",holdType:"ULD"}]});assert.deepEqual(buildHoldLayout(snap,d4()).holds.map(h=>h.name),["5"])});
test("incomplete D2 cannot render a diagram",()=>assert.throws(()=>buildHoldLayout(d2({uldApplicable:null}),d4()),/Complete all applicable/));
test("D2 can be configured without limits but a diagram cannot invent them",()=>assert.match(holdLayoutUnavailable(d2({bulkBalanceLimitsRequired:false,rows:[{...hold,balanceFrom:null,balanceTo:null}]}))!,/From and To/));
test("a bulk Hold without explicit limits is derived from its saved Area centroids",()=>{
  const areaHold={...hold,name:"ALB",balanceCentroid:null,balanceFrom:null,balanceTo:null,compartments:[{id:"5",areas:[
    {id:"51",maxWeight:374,maxVolume:1.47,indexPerWeightUnit:.024},
    {id:"52",maxWeight:353,maxVolume:1.39,indexPerWeightUnit:.025},
    {id:"53",maxWeight:770,maxVolume:3.02,indexPerWeightUnit:.027},
  ]}]};
  const snap=d2({bulkBalanceLimitsRequired:false,balanceFormula:{referenceArm:0,constantC:1000},rows:[areaHold]});
  assert.equal(holdLayoutUnavailable(snap),null);
  const layout=buildHoldLayout(snap,d4({doors:[]}));
  assert.equal(layout.holds[0].balanceFrom,23.5);
  assert.equal(layout.holds[0].balanceTo,28);
  assert.deepEqual(layout.holds[0].subdivisions.map(segment=>segment.id),["53","52","51"]);
  assert.ok(layout.boundaryNotes?.some(note=>note.includes("derived from its saved Area centroids")));
});
test("a calibrated legacy Hold 5 profile keeps an ALB overlay ahead of centroid inference",()=>{
  const areaHold={...hold,name:"ALB",balanceCentroid:null,balanceFrom:null,balanceTo:null,compartments:[{id:"5",areas:[
    {id:"51",maxWeight:374,maxVolume:1.47,indexPerWeightUnit:.024},
    {id:"52",maxWeight:353,maxVolume:1.39,indexPerWeightUnit:.025},
    {id:"53",maxWeight:770,maxVolume:3.02,indexPerWeightUnit:.027},
  ]}]};
  const snap=d2({bulkBalanceLimitsRequired:false,balanceFormula:{referenceArm:0,constantC:1000},rows:[areaHold]});
  const aircraft={...A319_LAYOUT,holdProfiles:{"5":{points:[{arm:24,halfWidth:4},{arm:25,halfWidth:3.5},{arm:27,halfWidth:2}]}}};
  const layout=build(snap,d4({doors:[]}),undefined,aircraft);
  assert.equal(layout.holds[0].balanceFrom,24);
  assert.equal(layout.holds[0].balanceTo,27);
  assert.equal(layout.usesGlobalHoldBoundaries,true);
  assert.ok(!layout.boundaryNotes?.some(note=>note.includes("Area centroids")));
});
test("A320-200 uses global aircraft-type hold boundaries when optional D2 limits are blank",()=>{
  const a320Hold={...hold,name:"1",balanceFrom:null,balanceTo:null};
  const a320D2=d2({typeCode:"320",subtype:"200",bulkBalanceLimitsRequired:false,rows:[a320Hold]});
  assert.equal(holdLayoutUnavailable(a320D2),null);
  const layout=buildHoldLayout(a320D2,d4({typeCode:"320",subtype:"200",doors:[]}));
  assert.equal(layout.usesGlobalHoldBoundaries,true);
  assert.equal(layout.holds[0].x,holdLayoutX(12.205,A320_LAYOUT));
  assert.ok(Math.abs(layout.holds[0].width-(12.205-7.255)*A320_LAYOUT.span/A320_LAYOUT.length)<1e-8);
});
test("carrier-supplied A320 hold boundaries override the global aircraft-type defaults",()=>{
  const a320Hold={...hold,name:"1",balanceCentroid:9.5,balanceFrom:8,balanceTo:11};
  const layout=buildHoldLayout(d2({typeCode:"320",subtype:"200",rows:[a320Hold]}),d4({typeCode:"320",subtype:"200",doors:[]}));
  assert.equal(layout.usesGlobalHoldBoundaries,false);
  assert.equal(layout.holds[0].x,holdLayoutX(11,A320_LAYOUT));
  assert.ok(Math.abs(layout.holds[0].width-(11-8)*A320_LAYOUT.span/A320_LAYOUT.length)<1e-8);
});
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
  assert.equal(layout.holds[0].x,holdLayoutX(31.212-2.735,A320_LAYOUT));
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
test("a fitted configuration contracts a bulk Hold to its applicable Area footprint",()=>{
  const areaHold={...hold,name:"ALF",balanceCentroid:29,balanceFrom:26,balanceTo:32,compartments:[{id:"3",areas:[
    {id:"31",maxWeight:1289,maxVolume:5.21,indexPerWeightUnit:.027,configurationCodes:["0ACT"]},
    {id:"32",maxWeight:1177,maxVolume:4.76,indexPerWeightUnit:.029,configurationCodes:["0ACT"]},
    {id:"33",maxWeight:1021,maxVolume:4.76,indexPerWeightUnit:.031,configurationCodes:[]},
  ]}]};
  const source=d2({fuelConfigurations:[{code:"0ACT",description:"None"},{code:"2ACT",description:"Two"}],balanceFormula:{referenceArm:0,constantC:1000},rows:[areaHold]});
  const effective=effectiveAircraftD2Snapshot(source,"2ACT");
  const layout=build(effective,d4({doors:[]}),undefined,A319_LAYOUT,source);
  assert.deepEqual(layout.holds[0].subdivisions.map(segment=>segment.id),["33"]);
  assert.equal(layout.holds[0].balanceFrom,30);
  assert.equal(layout.holds[0].balanceTo,32);
  assert.equal(layout.holds[0].x,holdLayoutX(32));
  assert.equal(layout.holds[0].width,holdLayoutX(30)-holdLayoutX(32));
});
test("a Hold ID labels an undivided Hold",()=>{
  const layout=buildHoldLayout(d2(),d4());
  assert.deepEqual(layout.holds[0].subdivisions.map(segment=>[segment.kind,segment.id]),[["HOLD","5"]]);
});
test("Compartment IDs label a Hold when no Areas or Bays exist",()=>{
  const compartmentHold={...hold,compartments:[{id:"5A",areas:[]},{id:"5B",areas:[]}]};
  const layout=buildHoldLayout(d2({rows:[compartmentHold]}),d4());
  assert.deepEqual(layout.holds[0].subdivisions.map(segment=>[segment.kind,segment.id]),[["COMPARTMENT","5B"],["COMPARTMENT","5A"]]);
  assert.ok(layout.holds[0].subdivisions.every(segment=>segment.width===layout.holds[0].width/2));
});
test("aircraft master compartment boundaries can align an internal divider to a door",()=>{
  const compartmentHold={...hold,compartments:[{id:"5A",areas:[]},{id:"5B",areas:[]}]};
  const aircraft={...A319_LAYOUT,holdSubdivisionBreaks:{"5":[25]}};
  const layout=build(d2({rows:[compartmentHold]}),d4(),undefined,aircraft);
  assert.deepEqual(layout.holds[0].subdivisions.map(segment=>segment.id),["5B","5A"]);
  assert.equal(layout.holds[0].subdivisions[1].x,holdLayoutX(25,aircraft));
});
test("split forward and aft hold codes inherit their family drawing offsets",()=>{
  const split=(name:string):AircraftD2HoldRow=>({...hold,name,holdType:"ULD",maxVolume:null,balanceCentroid:25,balanceFrom:20,balanceTo:30,compartments:[{id:"1",areas:[]}]});
  const snap=d2({bulkApplicable:false,uldApplicable:true,rows:[split("FLF"),split("ALA")]});
  const aircraft={...A319_LAYOUT,holdArmOffsets:{FWD:2,AFT:-2}};
  const layout=build(snap,d4({doors:[]}),undefined,aircraft);
  const forward=layout.holds.find(item=>item.name==="FLF")!,aft=layout.holds.find(item=>item.name==="ALA")!;
  assert.equal(forward.x,holdLayoutX(32,aircraft));
  assert.equal(aft.x,holdLayoutX(28,aircraft));
});
test("aft lower bulk inherits the aft-family drawing offset",()=>{
  const bulk={...hold,name:"ALB",balanceCentroid:31,balanceFrom:30,balanceTo:32};
  const snap=d2({rows:[bulk]});
  const aircraft={...A319_LAYOUT,holdArmOffsets:{AFT:-2}};
  const layout=build(snap,d4({doors:[]}),undefined,aircraft);
  assert.equal(layout.holds[0].x,holdLayoutX(30,aircraft));
  assert.equal(layout.holds[0].width,holdLayoutX(28,aircraft)-holdLayoutX(30,aircraft));
});
test("configured D3 physical positions become Bay subdivisions ordered by centroid",()=>{
  const uldHold={...hold,name:"FWD",holdType:"ULD" as const,maxVolume:null,compartments:[{id:"1",areas:[]}]};
  const a320D2=d2({typeCode:"320",subtype:"200",bulkApplicable:false,uldApplicable:true,rows:[uldHold]});
  const d3:AircraftD3Snapshot={canView:true,canEdit:true,revision:"r",typeCode:"320",subtype:"200",uldHolds:[{id:"FWD",compartments:["1"]}],uldTypes:["LD3-45"],configurations:[{holdId:"FWD",code:"100",description:"DEFAULT",expectedPositionCount:2,atomicBays:[
    {id:"11",compartmentId:"1",lateralCentroid:null,lateralFrom:null,lateralTo:null,balanceCentroid:10,balanceFrom:null,balanceTo:null,colour:null},
    {id:"12",compartmentId:"1",lateralCentroid:null,lateralFrom:null,lateralTo:null,balanceCentroid:11,balanceFrom:null,balanceTo:null,colour:null},
  ],rows:[
    {rowType:"POSITION",positionId:"11",occupiedBayIds:["11"],compartmentId:"1",uldCode:"AKE",uldType:"LD3-45",uldBaseCode:"K",groupId:null,maxWeight:1134,volume:null,lateralCentroid:null,lateralFrom:null,lateralTo:null,balanceCentroid:10,balanceFrom:null,balanceTo:null,indexPerWeightUnit:.01,colour:null},
    {rowType:"POSITION",positionId:"12",occupiedBayIds:["12"],compartmentId:"1",uldCode:"AKE",uldType:"LD3-45",uldBaseCode:"K",groupId:null,maxWeight:1134,volume:null,lateralCentroid:null,lateralFrom:null,lateralTo:null,balanceCentroid:11,balanceFrom:null,balanceTo:null,indexPerWeightUnit:.02,colour:null},
  ]}]};
  const layout=buildHoldLayout(a320D2,d4({typeCode:"320",subtype:"200",doors:[]}),d3);
  assert.deepEqual(layout.holds[0].subdivisions.map(segment=>segment.id),["12","11"]);
  assert.ok(layout.holds[0].subdivisions.every(segment=>segment.kind==="BAY"));
});
test("ULD display ranges separate adjacent positions and align L/R pairs",()=>{
  const source=[
    {id:"12L",compartmentId:"1",uldType:"LD3",uldCodes:["AKE"],x:10,width:8},
    {id:"12R",compartmentId:"1",uldType:"LD3",uldCodes:["AKE"],x:10.2,width:8},
    {id:"13L",compartmentId:"1",uldType:"LD3",uldCodes:["AKE"],x:15,width:8},
    {id:"13R",compartmentId:"1",uldType:"LD3",uldCodes:["AKE"],x:15.2,width:8},
    {id:"14L",compartmentId:"1",uldType:"LD3",uldCodes:["AKE"],x:20,width:8},
    {id:"14R",compartmentId:"1",uldType:"LD3",uldCodes:["AKE"],x:20.2,width:8},
  ];
  const positions=separateUldPositionDisplayRanges(source,8,24),byId=(id:string)=>positions.find(position=>position.id===id)!;
  assert.equal(byId("12L").x,byId("12R").x);
  assert.equal(byId("13L").x,byId("13R").x);
  assert.equal(byId("12L").x+byId("12L").width,byId("13L").x);
  assert.equal(byId("13L").x+byId("13L").width,byId("14L").x);
});
test("ULD display normalisation preserves the saved footprint for mutually exclusive layouts",()=>{
  const source=[
    {id:"12",compartmentId:"1",uldType:"LD8",uldCodes:["PLA"],x:10,width:6,sourceX:10,sourceWidth:6},
    {id:"13",compartmentId:"1",uldType:"LD8",uldCodes:["PLA"],x:13,width:6,sourceX:13,sourceWidth:6},
  ];
  const positions=separateUldPositionDisplayRanges(source,8,16);
  assert.notEqual(positions[0].width,positions[0].sourceWidth);
  assert.deepEqual(positions.map(position=>[position.sourceX,position.sourceWidth]),[[10,6],[13,6]]);
});
test("overlapping ULD positions become mutually exclusive overlay arrangements",()=>{
  const uldHold={...hold,name:"FLF",holdType:"ULD" as const,maxVolume:null,balanceCentroid:16.5,balanceFrom:13,balanceTo:20,compartments:[{id:"1",areas:[]}]};
  const snap=d2({bulkApplicable:false,uldApplicable:true,rows:[uldHold]});
  const bay=(id:string,from:number,to:number)=>({id,compartmentId:"1",lateralCentroid:null,lateralFrom:null,lateralTo:null,balanceCentroid:(from+to)/2,balanceFrom:from,balanceTo:to,colour:null});
  const row=(id:string,from:number,to:number):AircraftD3Snapshot["configurations"][number]["rows"][number]=>({rowType:"POSITION",positionId:id,occupiedBayIds:[id],compartmentId:"1",uldCode:"PKC",uldType:"LD1",uldBaseCode:"K",groupId:null,maxWeight:1587,volume:null,lateralCentroid:null,lateralFrom:null,lateralTo:null,balanceCentroid:(from+to)/2,balanceFrom:from,balanceTo:to,indexPerWeightUnit:.01,colour:null});
  const ranges:[[string,number,number],[string,number,number],[string,number,number],[string,number,number]]=[["11L",13.2,14.7],["12L",14.8,16.4],["13L",15.7,17.3],["14L",16.4,18]];
  const d3:AircraftD3Snapshot={canView:true,canEdit:true,revision:"r",typeCode:"319",subtype:"100",uldHolds:[{id:"FLF",compartments:["1"]}],uldTypes:["LD1"],configurations:[{holdId:"FLF",code:"A",description:"DEFAULT",expectedPositionCount:4,atomicBays:ranges.map(([id,from,to])=>bay(id,from,to)),rows:ranges.map(([id,from,to])=>row(id,from,to))}]};
  const layout=build(snap,d4({doors:[]}),d3,A319_LAYOUT);
  const selector=layout.uldArrangementSelectors[0];
  assert.notEqual(selector,undefined,JSON.stringify(layout.holds[0].uldPositions));
  assert.equal(selector.label,"HOLD FLF ARRANGEMENT");
  assert.deepEqual(selector.options.map(option=>option.label),["12 + 14","13"]);
  assert.ok(selector.options.every(option=>option.includedPositionIds.includes("11L")));
  assert.ok(!selector.options.some(option=>option.includedPositionIds.includes("12L")&&option.includedPositionIds.includes("13L")));
});
test("ULD family overlays combine code-specific lock arrangements into selectable bay positions",()=>{
  const uldHold={...hold,name:"FWD",holdType:"ULD" as const,maxVolume:null,balanceFrom:20,balanceTo:30,compartments:[{id:"1",areas:[]}]};
  const snap=d2({bulkApplicable:false,uldApplicable:true,rows:[uldHold]});
  const position=(uldCode:string,uldType:string,balanceFrom:number,balanceTo:number):AircraftD3Snapshot["configurations"][number]["rows"][number]=>({rowType:"POSITION",positionId:uldType==="LD3"?"11L":"11P",occupiedBayIds:uldType==="LD3"?["11L"]:["11L","11R"],compartmentId:"1",uldCode,uldType,uldBaseCode:"6",groupId:null,maxWeight:5000,volume:null,lateralCentroid:null,lateralFrom:null,lateralTo:null,balanceCentroid:(balanceFrom+balanceTo)/2,balanceFrom,balanceTo,indexPerWeightUnit:.01,colour:null});
  const d3:AircraftD3Snapshot={canView:true,canEdit:true,revision:"r",typeCode:"319",subtype:"100",uldHolds:[{id:"FWD",compartments:["1"]}],uldTypes:["LD3","LD7","LD8"],configurations:[{holdId:"FWD",code:"A",description:"DEFAULT",expectedPositionCount:2,atomicBays:[
    {id:"11L",compartmentId:"1",lateralCentroid:null,lateralFrom:null,lateralTo:null,balanceCentroid:24.5,balanceFrom:24,balanceTo:25,colour:null},
    {id:"11R",compartmentId:"1",lateralCentroid:null,lateralFrom:null,lateralTo:null,balanceCentroid:24.5,balanceFrom:24,balanceTo:25,colour:null},
  ],rows:[position("AKE","LD3",24,25),position("PAG","LD7",23.9,26.1),position("PMC","LD7",23.8,26.2),position("PLA","LD8",23.9,26.1)]}]};
  const layout=build(snap,d4({doors:[]}),d3,A319_LAYOUT),ld7=layout.holds[0].uldPositions.find(item=>item.uldType==="LD7")!;
  assert.deepEqual(layout.uldTypes,["LD3","LD7","LD8"]);
  assert.equal(layout.holds[0].uldPositions.filter(item=>item.uldType==="LD7").length,1);
  assert.deepEqual(ld7.uldCodes,["PAG","PMC"]);
  assert.deepEqual(ld7.codeRanges?.map(range=>range.uldCode),["PAG","PMC"]);
  assert.notEqual(ld7.codeRanges?.[0].width,ld7.codeRanges?.[1].width);
  assert.equal(ld7.id,"11P");
  assert.equal(ld7.x,holdLayoutX(26.2,A319_LAYOUT));
  assert.equal(ld7.width,holdLayoutX(23.8,A319_LAYOUT)-holdLayoutX(26.2,A319_LAYOUT));
});
test("aircraft master metadata exposes mutually exclusive ULD arrangements with their reference pallet footprint",()=>{
  const uldHold={...hold,name:"FWD",holdType:"ULD" as const,maxVolume:null,balanceFrom:20,balanceTo:30,compartments:[{id:"1",areas:[]}]};
  const snap=d2({bulkApplicable:false,uldApplicable:true,rows:[uldHold]});
  const row=(positionId:string,uldCode:string,uldType:string,balanceFrom:number,balanceTo:number):AircraftD3Snapshot["configurations"][number]["rows"][number]=>({
    rowType:"POSITION",positionId,occupiedBayIds:[positionId==="11P"||positionId==="11"?"11":"13"],compartmentId:"1",uldCode,uldType,uldBaseCode:"P",groupId:null,maxWeight:5000,volume:null,
    lateralCentroid:null,lateralFrom:null,lateralTo:null,balanceCentroid:(balanceFrom+balanceTo)/2,balanceFrom,balanceTo,indexPerWeightUnit:.01,colour:null,
  });
  const d3:AircraftD3Snapshot={canView:true,canEdit:true,revision:"r",typeCode:"319",subtype:"100",uldHolds:[{id:"FWD",compartments:["1"]}],uldTypes:["LD7","LD8"],configurations:[{
    holdId:"FWD",code:"A",description:"DEFAULT",expectedPositionCount:2,atomicBays:[
      {id:"11",compartmentId:"1",lateralCentroid:null,lateralFrom:null,lateralTo:null,balanceCentroid:22,balanceFrom:21,balanceTo:23,colour:null},
      {id:"13",compartmentId:"1",lateralCentroid:null,lateralFrom:null,lateralTo:null,balanceCentroid:25,balanceFrom:24,balanceTo:26,colour:null},
    ],rows:[row("11P","PAG","LD7",21,23.2),row("11P","PMC","LD7",21,23.4),row("11","PLA","LD8",21,22),row("13","PLA","LD8",24,25),row("14","PLA","LD8",24.7,25.7),row("15","PLA","LD8",26,27)],
  }]};
  const aircraft={...A319_LAYOUT,uldArrangementSelectors:[{holdId:"FWD",uldType:"LD8",label:"FWD HOLD ARRANGEMENT",options:[
    {id:"11P_PAG",label:"88″ PALLET AT 11P",includedPositionIds:["13","15"],referencePositionId:"11P",referenceUldCode:"PAG",excludedPositionIds:["14"]},
    {id:"11P_PMC",label:"96″ PALLET AT 11P",includedPositionIds:["14","15"],referencePositionId:"11P",referenceUldCode:"PMC",excludedPositionIds:["13"]},
  ]}]};
  const layout=build(snap,d4({doors:[]}),d3,aircraft),selector=layout.uldArrangementSelectors[0];
  assert.equal(selector.label,"FWD HOLD ARRANGEMENT");
  assert.deepEqual(selector.options.map(option=>[option.id,option.includedPositionIds,option.excludedPositionIds]),[["11P_PAG",["13","15"],["14"]],["11P_PMC",["14","15"],["13"]]]);
  assert.equal(selector.options[0].referencePosition!.x,holdLayoutX(23.2,aircraft));
  assert.equal(selector.options[1].referencePosition!.width,holdLayoutX(21,aircraft)-holdLayoutX(23.4,aircraft));
});
test("configured D3 bays retain the aircraft compartment boundary and follow its saved D4 door start",()=>{
  const uldHold={...hold,name:"AFT",holdType:"ULD" as const,maxVolume:null,compartments:[{id:"3",areas:[]},{id:"4",areas:[]}]};
  const snap=d2({bulkApplicable:false,uldApplicable:true,rows:[uldHold]});
  const d3:AircraftD3Snapshot={canView:true,canEdit:true,revision:"r",typeCode:"319",subtype:"100",uldHolds:[{id:"AFT",compartments:["3","4"]}],uldTypes:["AKE"],configurations:[{holdId:"AFT",code:"A",description:"DEFAULT",expectedPositionCount:2,atomicBays:[
    {id:"3",compartmentId:"3",lateralCentroid:null,lateralFrom:null,lateralTo:null,balanceCentroid:24,balanceFrom:null,balanceTo:null,colour:null},
    {id:"4",compartmentId:"4",lateralCentroid:null,lateralFrom:null,lateralTo:null,balanceCentroid:26,balanceFrom:null,balanceTo:null,colour:null},
  ],rows:[
    {rowType:"POSITION",positionId:"3",occupiedBayIds:["3"],compartmentId:"3",uldCode:"AKE",uldType:"AKE",uldBaseCode:"K",groupId:null,maxWeight:1134,volume:null,lateralCentroid:null,lateralFrom:null,lateralTo:null,balanceCentroid:24,balanceFrom:null,balanceTo:null,indexPerWeightUnit:.01,colour:null},
    {rowType:"POSITION",positionId:"4",occupiedBayIds:["4"],compartmentId:"4",uldCode:"AKE",uldType:"AKE",uldBaseCode:"K",groupId:null,maxWeight:1134,volume:null,lateralCentroid:null,lateralFrom:null,lateralTo:null,balanceCentroid:26,balanceFrom:null,balanceTo:null,indexPerWeightUnit:.02,colour:null},
  ]}]};
  const aircraft={...A319_LAYOUT,holdSubdivisionBreaks:{AFT:[25]},holdSubdivisionDoorStarts:{AFT:["AFT"]}};
  const doors=d4({doors:[{holdId:"AFT",holdType:"ULD",deckName:"Lower Deck",forwardArm:24.5,aftArm:25.5,height:1,orientation:"R"}]});
  const layout=build(snap,doors,d3,aircraft);
  assert.deepEqual(layout.holds[0].subdivisions.map(segment=>segment.id),["4","3"]);
  assert.equal(layout.holds[0].subdivisions[1].x,holdLayoutX(24.5,aircraft));
});

test("configured D3 physical bays expand a stale D2 ULD outline instead of being clipped",()=>{
  const uldHold={...hold,name:"ALF",holdType:"ULD" as const,maxVolume:null,balanceCentroid:26,balanceFrom:25,balanceTo:27,compartments:[{id:"3",areas:[]}]};
  const snap=d2({bulkApplicable:false,uldApplicable:true,rows:[uldHold]});
  const d3:AircraftD3Snapshot={canView:true,canEdit:true,revision:"r",typeCode:"319",subtype:"100",uldHolds:[{id:"ALF",compartments:["3"]}],uldTypes:["LD1"],configurations:[{
    holdId:"ALF",code:"A",description:"DEFAULT",expectedPositionCount:3,atomicBays:[
      {id:"31L",compartmentId:"3",lateralCentroid:null,lateralFrom:null,lateralTo:null,balanceCentroid:24.5,balanceFrom:24,balanceTo:25,colour:null},
      {id:"32L",compartmentId:"3",lateralCentroid:null,lateralFrom:null,lateralTo:null,balanceCentroid:25.5,balanceFrom:25,balanceTo:26,colour:null},
      {id:"33L",compartmentId:"3",lateralCentroid:null,lateralFrom:null,lateralTo:null,balanceCentroid:26.5,balanceFrom:26,balanceTo:27,colour:null},
    ],rows:[{rowType:"POSITION",positionId:"31L",occupiedBayIds:["31L"],compartmentId:"3",uldCode:"PKC",uldType:"LD1",uldBaseCode:"K",groupId:null,maxWeight:1000,volume:null,lateralCentroid:null,lateralFrom:null,lateralTo:null,balanceCentroid:24.5,balanceFrom:24,balanceTo:25,indexPerWeightUnit:.01,colour:null}],
  }]};
  const layout=build(snap,d4({doors:[]}),d3,A319_LAYOUT);
  assert.equal(layout.holds[0].balanceFrom,24);
  assert.equal(layout.holds[0].balanceTo,27);
  assert.deepEqual(layout.holds[0].subdivisions.map(segment=>segment.id),["33L","32L","31L"]);
  assert.ok(layout.boundaryNotes?.some(note=>note.includes("expanded to include every configured D3 physical bay")));
});

test("missing D2 limits use D3 occupied ranges independently per deck and identify undrawn bulk holds",()=>{
  const uld=(deckCode:string):AircraftD2HoldRow=>({...hold,id:`${deckCode}:FWD`,name:"FWD",holdType:"ULD",deckCode,balanceCentroid:null,balanceFrom:null,balanceTo:null,compartments:[{id:"1",areas:[]}]});
  const snap=d2({uldApplicable:true,rows:[uld("MAIN"),uld("LOWER"),{...hold,balanceFrom:null,balanceTo:null}],deckTypes:[{code:"MAIN",name:"Main Deck"},{code:"LOWER",name:"Lower Deck"}]});
  const config=(holdId:string,from:number):AircraftD3Snapshot["configurations"][number]=>({holdId,code:"A",description:"Default",expectedPositionCount:1,atomicBays:[{id:"11",compartmentId:"1",colour:null,balanceCentroid:from+1,balanceFrom:from,balanceTo:from+2,lateralCentroid:null,lateralFrom:null,lateralTo:null}],rows:[{rowType:"POSITION",positionId:"11",occupiedBayIds:["11"],compartmentId:"1",uldCode:"AKH",uldType:"LD3-45",uldBaseCode:"K",groupId:null,maxWeight:1000,volume:null,lateralCentroid:null,lateralFrom:null,lateralTo:null,balanceCentroid:from+1,balanceFrom:from,balanceTo:from+2,indexPerWeightUnit:.01,colour:null}]});
  const positions:AircraftD3Snapshot={canView:true,canEdit:true,revision:"r",typeCode:"319",subtype:"100",uldHolds:[],uldOptions:[],uldTypes:[],configurations:[config("MAIN:FWD",10),config("LOWER:FWD",15)]};
  const layout=buildHoldLayout(snap,d4({doors:[]}),positions);
  assert.deepEqual(layout.holds.map(h=>[h.deckCode,h.balanceFrom,h.balanceTo]),[["MAIN",10,12],["LOWER",15,17]]);
  assert.equal(layout.decks.length,2);
  assert.equal(layout.boundaryNotes?.filter(n=>n.includes("occupied D3")).length,2);
  assert.ok(layout.boundaryNotes?.some(n=>n.includes("Hold 5: not drawn")));
  assert.equal(snap.rows[0].balanceFrom,null);
  // D2 supplied limits remain authoritative, and data from another aircraft is never used.
  const explicit=d2({...snap,bulkApplicable:false,rows:[{...uld("MAIN"),balanceFrom:9,balanceTo:13}]});
  assert.equal(buildHoldLayout(explicit,d4({doors:[]}),positions).holds[0].balanceFrom,9);
  assert.throws(()=>buildHoldLayout(snap,d4(),{...positions,subtype:"P2F"}),/No hold ranges/);
  assert.throws(()=>buildHoldLayout(snap,d4(),{...positions,canView:false}),/No hold ranges/);
});

test("unknown main-deck doors never become zero-width doors when D4 is configured",()=>{
 const main={...hold,id:"MAIN:FWD",name:"FWD",holdType:"ULD" as const,deckCode:"MAIN"};
 const snap=d2({uldApplicable:true,rows:[hold,main]});
 const doors=d4({doors:[...d4().doors,{holdId:"MAIN:FWD",holdType:"ULD",deckName:"Main Deck",forwardArm:null,aftArm:null,height:null,orientation:null}]});
 const layout=buildHoldLayout(snap,doors);
 assert.equal(layout.doors.length,1);assert.equal(layout.doors[0].holdId,"5");
});

test("a saved door remains visible when its bulk hold boundary is not yet drawable",()=>{
 const uld={...hold,id:"LOWER:FWD",name:"FWD",holdType:"ULD" as const,balanceCentroid:null,balanceFrom:10,balanceTo:14};
 const bulk={...hold,id:"LOWER:ALB",name:"ALB",balanceFrom:null,balanceTo:null};
 const snap=d2({uldApplicable:true,bulkBalanceLimitsRequired:false,uldBalanceLimitsRequired:false,rows:[uld,bulk]});
 const doors=d4({doors:[
  {...d4().doors[0],holdId:"LOWER:FWD",holdType:"ULD",forwardArm:9,aftArm:10},
  {...d4().doors[0],holdId:"LOWER:ALB",forwardArm:25,aftArm:26},
 ]});
 const positions:AircraftD3Snapshot={canView:true,canEdit:true,revision:"r",typeCode:"319",subtype:"100",uldHolds:[],uldOptions:[],uldTypes:[],configurations:[]};
 const layout=buildHoldLayout(snap,doors,positions);
 assert.deepEqual(layout.holds.map(item=>item.name),["FWD"]);
 assert.deepEqual(layout.doors.map(item=>item.holdId),["LOWER:FWD","LOWER:ALB"]);
});
