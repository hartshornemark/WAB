import test from "node:test";
import assert from "node:assert/strict";
import {buildSeatMap as build,seatMapUnavailable} from "../src/domain/seat-map";
import {holdLayoutX} from "../src/domain/hold-layout";
import {A319_LAYOUT,A320_LAYOUT,aircraftLayoutFor} from "./fixtures/aircraft-layouts";
import type {D9Configuration} from "../src/domain/aircraft-d9";
const buildSeatMap=(d8:AircraftD8Snapshot,c4:AircraftC4Snapshot,d5:AircraftD5Snapshot,configuration?:D9Configuration)=>build(d8,c4,d5,configuration,aircraftLayoutFor(d8.typeCode,d8.subtype)!);
import type {AircraftD8Snapshot} from "../src/domain/aircraft-d8";
import type {AircraftD5Snapshot} from "../src/domain/aircraft-d5";
import type {AircraftC4Snapshot} from "../src/domain/aircraft-c4";
const base={canView:true,canEdit:true,revision:"r",typeCode:"319",subtype:"100"};
const c4:AircraftC4Snapshot={...base,exists:true,lengthUnit:"M",values:{datum:2.54,referenceArm:10,constantK:50,constantC:1000,macRcLength:4,lemacLerc:12}};
const d8:AircraftD8Snapshot={...base,excludedRows:[2],cabinAreas:[{id:"A",rowFrom:1,rowTo:4,seatGrouping:"2-2"}],rows:[1,3,4].map((rowNumber,i)=>({areaId:"A",rowNumber,maximumSeats:4,maximumWeight:null,centroid:999,index:i===2?.005:.001*i}))};
const d5:AircraftD5Snapshot={...base,excludedRows:[2],cabinAreas:[{id:"A",deck:"MAIN",startRow:1,endRow:4,centroid:10,startArm:null,endArm:null,index:0}],flightDeckLocations:[],cabinCrewLocations:[]};
test("seat map uses current C4 index conversion and excludes omitted rows",()=>{
 const rows=buildSeatMap(d8,c4,d5).decks[0].rows;
 assert.deepEqual(rows.map(r=>r.rowNumber),[1,3,4]);assert.deepEqual(rows.map(r=>r.centroid),[10,11,15]);
 assert.equal(rows[0].x,holdLayoutX(10,A319_LAYOUT));assert.ok(Math.abs((rows[2].x-rows[1].x)-4*(rows[1].x-rows[0].x))<1e-9);
});
test("seat map uses carrier nose arm and no cargo offsets",()=>{
 const snapshot={...d8,typeCode:"320",subtype:"200"};
 const formula={...c4,typeCode:"320",subtype:"200",values:{...c4.values,datum:1}};
 const result=buildSeatMap(snapshot,formula,{...d5,typeCode:"320",subtype:"200"});
 assert.equal(result.decks[0].rows[0].x,holdLayoutX(10,{...A320_LAYOUT,noseArm:1}));
});
test("seat grouping override controls the drawn row",()=>{
 const result=buildSeatMap({...d8,rows:d8.rows.map((r,i)=>i? r:{...r,seatGroupingOverride:"1-3"})},c4,d5);
 assert.deepEqual(result.decks[0].rows[0].groups,[1,3]);
});
test("seat map renders a 1-2-1 row as three groups and two aisles",()=>{
 const result=buildSeatMap({...d8,cabinAreas:[{...d8.cabinAreas[0],seatGrouping:"1-2-1"}]},c4,d5);
 assert.deepEqual(result.decks[0].rows[0].groups,[1,2,1]);
 assert.equal(result.decks[0].rows[0].seats,4);
});
test("seat map requires explicit grouping, without assuming symmetry",()=>{
 assert.match(seatMapUnavailable({...d8,cabinAreas:[{...d8.cabinAreas[0],seatGrouping:null}]})!,/grouping/);
 assert.match(seatMapUnavailable({...d8,cabinAreas:[{...d8.cabinAreas[0],seatGrouping:"3-3"}]})!,/match/);
});
test("seat map rejects coincident and out-of-aircraft rows",()=>{
 assert.throws(()=>buildSeatMap({...d8,rows:d8.rows.map(r=>({...r,index:0}))},c4,d5),/same plotted position/);
 assert.throws(()=>buildSeatMap({...d8,rows:d8.rows.map(r=>({...r,index:1}))},c4,d5),/outside/);
});
test("seat map validates configured formula, access and matching aircraft",()=>{
 assert.throws(()=>buildSeatMap(d8,{...c4,exists:false},d5),/Configure C4/);
 assert.throws(()=>buildSeatMap(d8,c4,{...d5,canView:false}),/match/);
 assert.throws(()=>buildSeatMap({...d8,typeCode:"777"},c4,d5),/outline/);
 assert.match(seatMapUnavailable({...d8,canView:false})!,/permission/);
});

test("blocked centres retain six physical positions and four usable seats",()=>{
 const result=buildSeatMap({...d8,rows:d8.rows.map((r,i)=>i?r:{...r,seatGroupingOverride:"3-3:B"})},c4,d5);
 const [blocked,normal]=result.decks[0].rows;
 assert.deepEqual(blocked.groups,[3,3]);
 assert.equal(blocked.blockedCentres,true);
 assert.equal(blocked.seats,4);
 assert.equal(normal.blockedCentres,false);
 assert.deepEqual(normal.groups,[2,2]);
});

test("area labels use the D5 centroid calculated with current C4, not the row midpoint",()=>{
 const result=buildSeatMap(d8,c4,{...d5,cabinAreas:[{...d5.cabinAreas[0],centroid:999,index:.002}]});
 assert.equal(result.decks[0].areas[0].centroid,12);
 assert.equal(result.decks[0].areas[0].x,holdLayoutX(12,A319_LAYOUT));
});

test("D9 configurations share physical rows but apply blocked centres independently",()=>{
 const physical={...d8,cabinAreas:[{...d8.cabinAreas[0],seatGrouping:"3-3"}],rows:d8.rows.map(r=>({...r,maximumSeats:6}))};
 const area={areaId:"A",classSeats:[18,0,0,0] as [number,number,number,number],totalSeats:18,centroid:10,from:null,to:null,index:0};
 const a=buildSeatMap(physical,c4,d5,{code:"A",description:"Y18",rows:[area]});
 const b=buildSeatMap(physical,c4,d5,{code:"B",description:"C4Y12",rows:[{...area,totalSeats:16,blockedRows:[1]}]});
 assert.equal(a.decks[0].rows.reduce((s,r)=>s+r.seats,0),18);
 assert.equal(b.decks[0].rows.reduce((s,r)=>s+r.seats,0),16);
 assert.equal(a.decks[0].rows[0].blockedCentres,false);
 assert.equal(b.decks[0].rows[0].blockedCentres,true);
 assert.deepEqual(a.decks[0].rows.map(r=>r.x),b.decks[0].rows.map(r=>r.x));
 assert.throws(()=>buildSeatMap(physical,c4,d5,{code:"B",description:"bad",rows:[{...area,blockedRows:[1]}]}),/usable seats/);
 assert.throws(()=>buildSeatMap(physical,c4,d5,{code:"B",description:"bad",rows:[{...area,blockedRows:[2]}]}),/Row 2/);
});

test("empty groups preserve the opposite side of the aisle",async()=>{
 const {seatMapGroupSlots,seatMapGroupStarts}=await import("../src/domain/seat-map");
 const full=seatMapGroupStarts([2,2],3);
 assert.deepEqual(seatMapGroupSlots([0,2],[[2,2]]),[2,2]);
 assert.deepEqual(seatMapGroupStarts(seatMapGroupSlots([0,2],[[2,2]]),3),full);
 assert.deepEqual(seatMapGroupSlots([2,0],[]),[2,2]);
 assert.ok(full[1]>0);assert.ok(full[0]+3<0);
});

test("one close row pair cannot collapse all seat glyphs",async()=>{
 const {seatMapSeatDepth,seatMapOverlaps}=await import("../src/domain/seat-map");
 const rows=[0,10,20,20.6,30,40].map((x,i)=>({x,rowNumber:i+1,areaId:"A",centroid:x,groups:[2,2],blockedCentres:false,seats:4}));
 assert.equal(seatMapSeatDepth(rows),2.7);
 assert.deepEqual(seatMapOverlaps(rows),[[3,4]]);
 assert.equal(seatMapSeatDepth([{x:0}]),2.7);
 assert.deepEqual(seatMapOverlaps(rows.filter(r=>r.rowNumber!==4)),[]);
});
