import test from"node:test";
import assert from"node:assert/strict";
import{aircraftC7Statuses,idealTrimStatus,tippingLimitsStatus}from"../src/domain/aircraft-c7-status";
import type{AircraftC7Point,AircraftC7Values}from"../src/domain/aircraft-c7";

const point=(weight=35000):AircraftC7Point=>({weight,indexValue:20,macValue:null});
const values=():AircraftC7Values=>({idealTrim:{enabled:false,points:[]},tippingLimits:{enabled:false,points:[]}});

test("skips Ideal Trim when unchecked",()=>assert.equal(idealTrimStatus({enabled:false,points:[]},70000),"skipped"));
test("marks checked Ideal Trim incomplete with no data",()=>assert.equal(idealTrimStatus({enabled:true,points:[]},70000),"incomplete"));
test("marks checked Ideal Trim partial with one row",()=>assert.equal(idealTrimStatus({enabled:true,points:[point()]},70000),"partial"));
test("configures checked Ideal Trim with at least two valid rows",()=>assert.equal(idealTrimStatus({enabled:true,points:[point(),point(50000)]},70000),"configured"));
test("skips Tipping Limits when unchecked",()=>assert.equal(tippingLimitsStatus({enabled:false,points:[]},70000),"skipped"));
test("marks checked Tipping Limits incomplete with no row",()=>assert.equal(tippingLimitsStatus({enabled:true,points:[]},70000),"incomplete"));
test("configures checked Tipping Limits with one valid row",()=>assert.equal(tippingLimitsStatus({enabled:true,points:[point()]},70000),"configured"));
test("skips the page when both supported sections are unchecked",()=>assert.equal(aircraftC7Statuses(values(),70000).page,"skipped"));
test("configures the page when every applicable section is configured",()=>{const input=values();input.idealTrim={enabled:true,points:[point(),point(50000)]};assert.equal(aircraftC7Statuses(input,70000).page,"configured")});
test("marks the page partial when applicable sections have mixed results",()=>{const input=values();input.idealTrim={enabled:true,points:[point()]};input.tippingLimits={enabled:true,points:[point()]};assert.equal(aircraftC7Statuses(input,70000).page,"partial")});
