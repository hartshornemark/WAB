import test from"node:test";import assert from"node:assert/strict";import{aircraftC4Status}from"../src/domain/aircraft-c4-status";import type{AircraftC4Snapshot}from"../src/domain/aircraft-c4";
const snapshot=(exists:boolean,values:AircraftC4Snapshot["values"]):AircraftC4Snapshot=>({canView:true,canEdit:true,exists,revision:"1",typeCode:"319",subtype:"100",lengthUnit:"M",values});
const complete={datum:2.54,referenceArm:17.25,constantK:50,constantC:1000,macRcLength:4.193,lemacLerc:16.202};
test("C4 is configured only when every value is valid",()=>assert.equal(aircraftC4Status(snapshot(true,complete)),"configured"));
test("C4 is partial when a saved row contains some but not all valid data",()=>assert.equal(aircraftC4Status(snapshot(true,{...complete,constantC:Number.NaN,macRcLength:Number.NaN})),"partial"));
test("C4 is incomplete when no saved record exists",()=>assert.equal(aircraftC4Status(snapshot(false,{datum:0,referenceArm:0,constantK:0,constantC:0,macRcLength:0,lemacLerc:0})),"incomplete"));
test("C4 is incomplete when a saved legacy row has no entered values",()=>assert.equal(aircraftC4Status(snapshot(true,{datum:Number.NaN,referenceArm:Number.NaN,constantK:Number.NaN,constantC:Number.NaN,macRcLength:Number.NaN,lemacLerc:Number.NaN})),"incomplete"));
