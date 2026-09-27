import test from"node:test";
import assert from"node:assert/strict";
import{aircraftC5Statuses,c5EnvelopeStatus}from"../src/domain/aircraft-c5-status";
import type{AircraftC5Values}from"../src/domain/aircraft-c5";

const boundary=(maximum:number)=>({fwd:[{weight:35000,indexValue:20,macValue:null},{weight:maximum,indexValue:45,macValue:null}],aft:[{weight:35000,indexValue:30,macValue:null},{weight:maximum,indexValue:60,macValue:null}]});
const complete=():AircraftC5Values=>({curtailed:false,inputMode:"INDEX",effectiveDow:35000,effectiveDowSource:"fleet",maximumWeights:{mrw:70500,tow:70000,law:62500,zfw:58500},envelopes:{tow:boundary(70000),law:boundary(62500),zfw:boundary(58500)}});

test("configures C5.1 when every required maximum and envelope is valid",()=>assert.equal(aircraftC5Statuses(complete()).page,"configured"));
test("allows every optional MAC value to remain null",()=>{const values=complete();assert.equal(aircraftC5Statuses(values).page,"configured")});
test("requires an Index value on every envelope row",()=>{const values=complete();values.envelopes.zfw.fwd[0].indexValue=Number.NaN;assert.equal(c5EnvelopeStatus(values,"zfw"),"partial")});
test("allows related maximums to be entered later but rejects a present hierarchy conflict",()=>{const missing=complete();missing.maximumWeights.mrw=0;assert.equal(c5EnvelopeStatus(missing,"tow"),"configured");const invalid=complete();invalid.maximumWeights.law=70100;assert.equal(c5EnvelopeStatus(invalid,"law"),"partial")});
test("requires ordered rows and applies the DOW lower bound to the zero-fuel envelope",()=>{const values=complete();values.envelopes.tow.fwd=[values.envelopes.tow.fwd[1],values.envelopes.tow.fwd[0]];assert.equal(c5EnvelopeStatus(values,"tow"),"partial");const high=complete();high.effectiveDow=34000;assert.equal(c5EnvelopeStatus(high,"zfw"),"partial")});
test("allows take-off and landing envelopes to begin above DOW",()=>{const values=complete();values.effectiveDow=34000;assert.equal(c5EnvelopeStatus(values,"tow"),"configured");assert.equal(c5EnvelopeStatus(values,"law"),"configured")});
test("requires the final FWD and AFT rows to equal the applicable maximum",()=>{const values=complete();values.envelopes.law.aft.at(-1)!.weight=62400;assert.equal(c5EnvelopeStatus(values,"law"),"partial")});
test("configures a complete ZFW envelope before DOW and MLAW are available",()=>{const values=complete();values.effectiveDow=0;values.effectiveDowSource="unavailable";values.maximumWeights.law=0;assert.equal(c5EnvelopeStatus(values,"zfw"),"configured")});
