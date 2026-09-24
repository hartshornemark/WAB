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
