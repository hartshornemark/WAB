import test from"node:test";import assert from"node:assert/strict";import{AircraftD8Invalid,buildD8Rows,validateD8Rows,type AircraftD8Snapshot,type SeatRow}from"../src/domain/aircraft-d8";import{aircraftD8Status,d8CabinAreaStatus}from"../src/domain/aircraft-d8-status";
const areas=[{id:"0A",rowFrom:1,rowTo:2},{id:"0B",rowFrom:3,rowTo:3}],row=(n:number,a:string):SeatRow=>({areaId:a,rowNumber:n,maximumSeats:4,maximumWeight:null,centroid:10+n,index:.001*n}),snap=(rows:SeatRow[],excludedRows:number[]=[]):AircraftD8Snapshot=>({canView:true,canEdit:true,revision:"r",typeCode:"319",subtype:"100",excludedRows,cabinAreas:areas,rows});
const formula={referenceArm:18.85,constantC:838.7};
test("D8 configures only when every D5-derived row is complete",()=>assert.equal(aircraftD8Status(snap([row(1,"0A"),row(2,"0A"),row(3,"0B")])) ,"configured"));
test("D8 is partial when each area is represented but a required row is missing",()=>assert.equal(aircraftD8Status(snap([row(1,"0A"),row(3,"0B")])) ,"partial"));
test("D8 is incomplete without completed rows",()=>assert.equal(aircraftD8Status(snap([])),"incomplete"));
test("D8 builds every row from D5 ranges and assigns its area",()=>assert.deepEqual(buildD8Rows(areas,[]).map(r=>[r.areaId,r.rowNumber]),[["0A",1],["0A",2],["0B",3]]));
test("D8 omits D5 Excluded Row Numbers from generated rows and completion",()=>{assert.deepEqual(buildD8Rows(areas,[],[2]).map(r=>r.rowNumber),[1,3]);assert.equal(aircraftD8Status(snap([row(1,"0A"),row(3,"0B")],[2])),"configured")});
test("D8 rejects a submitted excluded row",()=>assert.throws(()=>validateD8Rows([row(2,"0A")],areas,formula,[2]),/excluded on D5/));
test("D8 permits nullable maximum weight",()=>assert.equal(validateD8Rows([row(1,"0A")],areas,formula)[0].maximumWeight,null));
test("D8 rejects rows outside their D5 cabin area",()=>assert.throws(()=>validateD8Rows([row(3,"0A")],areas,formula),AircraftD8Invalid));
test("D8 saves completed rows progressively and ignores untouched generated rows",()=>assert.equal(validateD8Rows([row(1,"0A"),{areaId:"0A",rowNumber:2,maximumSeats:null,maximumWeight:null,centroid:null,index:null}],areas,formula).length,1));
test("D8 calculates Balance Arm Centroid from a decimal Index Per Weight Unit",()=>{const result=validateD8Rows([{...row(1,"0A"),centroid:null,index:"-0.00972"}],areas,formula);assert.equal(result[0].index,-0.00972);assert.equal(result[0].centroid,10.697836)});
test("D8 requires C4 before calculating Balance Arm Centroid",()=>assert.throws(()=>validateD8Rows([row(1,"0A")],areas,null),/Configure C4/));

test("each D8 cabin-area section reports its own completion",()=>{assert.equal(d8CabinAreaStatus([row(1,"0A")],2),"partial");assert.equal(d8CabinAreaStatus([row(1,"0A"),row(2,"0A")],2),"configured")});
test("D8 is not required for a Freighter",()=>assert.equal(aircraftD8Status(snap([]),"FREIGHTER"),"not_required"));

test("D8 inherits a cabin-area grouping without storing a row override",()=>{
 const result=validateD8Rows([row(1,"0A")],[{...areas[0],seatGrouping:"2-2"}],formula);
 assert.equal(result[0].seatGroupingOverride,null);
});
test("D8 rejects inherited grouping that disagrees with row seats",()=>{
 assert.throws(()=>validateD8Rows([row(1,"0A")],[{...areas[0],seatGrouping:"3-3"}],formula),/Row 1:.*6 seats.*4/);
});
test("D8 validates row overrides instead of the area default",()=>{
 const result=validateD8Rows([{...row(1,"0A"),seatGroupingOverride:" 1 – 3 "}],[{...areas[0],seatGrouping:"3-3"}],formula);
 assert.equal(result[0].seatGroupingOverride,"1-3");
});
test("D8 rejects malformed and mismatching row overrides",()=>{
 for(const grouping of ["0-0","2--2","2.5-1.5","2-2-2","2 2"])
 assert.throws(()=>validateD8Rows([{...row(1,"0A"),seatGroupingOverride:grouping}],areas,formula),AircraftD8Invalid);
});
test("D8 clearing an override restores inherited validation",()=>{
 assert.throws(()=>validateD8Rows([{...row(1,"0A"),seatGroupingOverride:""}],[{...areas[0],seatGrouping:"3-3"}],formula),/Row 1/);
});
test("D8 allows row-specific grouping with no area default",()=>{
 assert.equal(validateD8Rows([{...row(1,"0A"),seatGroupingOverride:"2-2"}],areas,formula)[0].seatGroupingOverride,"2-2");
});

test("D8 blocked centres preserve physical 3-3 while validating four usable seats",()=>{
 const result=validateD8Rows([{...row(1,"0A"),seatGroupingOverride:"3-3:B"}],areas,formula);
 assert.equal(result[0].seatGroupingOverride,"3-3:B");
 assert.equal(result[0].maximumSeats,4);
 assert.throws(()=>validateD8Rows([{...row(1,"0A"),maximumSeats:6,seatGroupingOverride:"3-3:B"}],areas,formula),/Maximum Seats/);
 for(const grouping of ["2-2:B","3-4:B","3-3:X"])
 assert.throws(()=>validateD8Rows([{...row(1,"0A"),seatGroupingOverride:grouping}],areas,formula));
});

test("D8 follows explicit row order and retains saved data by row identity",()=>{
 const explicit=[{id:"0A",rowFrom:1,rowTo:13,rowSequence:[13,1,2,3,4]}];
 const saved=[13,1,2,3,4].map(n=>row(n,"0A"));
 const built=buildD8Rows(explicit,saved);
 assert.deepEqual(built.map(r=>r.rowNumber),[13,1,2,3,4]);assert.equal(built[0].index,saved[0].index);
 assert.equal(aircraftD8Status({...snap(saved),cabinAreas:explicit}),"configured");
 assert.throws(()=>validateD8Rows([row(5,"0A")],explicit,formula),AircraftD8Invalid);
 assert.deepEqual(buildD8Rows(explicit,[],[2]).map(r=>r.rowNumber),[13,1,3,4]);
});

 test("D8 accepts an empty group while counting only physical seats",()=>{for(const grouping of ["0-2","2-0"]){assert.equal(validateD8Rows([{...row(1,"0A"),maximumSeats:2,seatGroupingOverride:grouping}],areas,formula)[0].seatGroupingOverride,grouping);}});

test('D8 validates gaps and reports actual aircraft rows, not list positions',()=>{
 const cabins=[{id:'0A',rowFrom:1,rowTo:3},{id:'0B',rowFrom:6,rowTo:15}];
 const rows=[row(1,'0A'),row(2,'0A'),row(3,'0A'),row(6,'0B'),row(7,'0B')];
 assert.equal(validateD8Rows(rows,cabins,formula).length,5);
 assert.throws(()=>validateD8Rows(rows.map(r=>r.rowNumber===6?{...r,index:null}:r),cabins,formula),/Index per Weight Unit at row 6 in Cabin Area 0B/);
 assert.throws(()=>validateD8Rows(rows.map(r=>r.rowNumber===7?{...r,index:null}:r),cabins,formula),/Index per Weight Unit at row 7 in Cabin Area 0B/);
});

import {suggestedD8Seats} from '../src/domain/aircraft-d8';
test('D8 suggests seat counts for default and override groups without accepting partial typing',()=>{
 assert.equal(suggestedD8Seats('3-3'),6);assert.equal(suggestedD8Seats('2-2'),4);
 assert.equal(suggestedD8Seats('0-2'),2);assert.equal(suggestedD8Seats('2-4-2'),8);
 assert.equal(suggestedD8Seats('3-'),null);assert.equal(suggestedD8Seats(''),null);
});
