import test from"node:test";import assert from"node:assert/strict";import{validateAircraftC11}from"../src/domain/aircraft-c11";import{aircraftC11Status}from"../src/domain/aircraft-c11-status";
const values={macFwdLimit:14,macAftLimit:41,stabMaxValue:3.5,stabMinValue:-3,variationFwd:18,variationAft:41,rateOfChange:-0.282608695652174};
test("accepts a variation range contained by the MAC limits",()=>assert.deepEqual(validateAircraftC11(values),{macFwdLimit:14,macAftLimit:41,stabMaxValue:3.5,stabMinValue:-3,variationFwd:18,variationAft:41}));
test("accepts signed decimal stabiliser values entered as text",()=>assert.deepEqual(validateAircraftC11({...values,stabMaxValue:"2.5",stabMinValue:"-2.5"}),{macFwdLimit:14,macAftLimit:41,stabMaxValue:2.5,stabMinValue:-2.5,variationFwd:18,variationAft:41}));
test("rejects a reversed variation range",()=>assert.throws(()=>validateAircraftC11({...values,variationFwd:42}),/variation range/));
test("marks a complete stored C11.1 record configured",()=>assert.equal(aircraftC11Status({canView:true,canEdit:true,exists:true,revision:"r",typeCode:"319",subtype:"100",values}),"configured"));
test("marks a missing C11.1 record incomplete",()=>assert.equal(aircraftC11Status({canView:true,canEdit:true,exists:false,revision:"",typeCode:"319",subtype:"100",values}),"incomplete"));

import { aircraftC11Required } from "../src/domain/aircraft-c11-status";
import type { C2Output } from "../src/domain/aircraft-c2";
const output=(code:string,selection:Partial<C2Output>={}):C2Output=>({code,name:code,group:"balance",displayOrder:1,validEdpPrelim:true,validAcarsPrelim:true,validEdpFinal:true,validAcarsFinal:true,selectedEdpPrelim:false,selectedAcarsPrelim:false,selectedEdpFinal:false,selectedAcarsFinal:false,...selection});
test("C11 is not required when neither stabiliser output is selected",()=>{
 assert.equal(aircraftC11Required({outputs:[output("STABTO"),output("STABLA"),output("OTHER",{selectedEdpFinal:true})]}),false);
 for(const exists of [false,true])assert.equal(aircraftC11Status({canView:true,canEdit:true,exists,revision:"r",typeCode:"319",subtype:"100",values},false),"not_required");
});
test("either stabiliser output in any document format requires C11",()=>{
 for(const code of ["STABTO","STABLA"])for(const field of ["selectedEdpPrelim","selectedAcarsPrelim","selectedEdpFinal","selectedAcarsFinal"]){
  assert.equal(aircraftC11Required({outputs:[output(code,{[field]:true})]}),true);
 }
});

import {stabiliserZeroTrim} from '../src/domain/aircraft-c11';
test('zero trim intersects at 28.37 percent MAC for the supplied chart',()=>{
 const zero=stabiliserZeroTrim({...values,variationFwd:20,variationAft:40,stabMaxValue:1.8,stabMinValue:-2.5,rateOfChange:-.215});
 assert.equal(zero?.from.toFixed(2),'28.37');assert.equal(zero?.from,zero?.to);
});
test('zero trim handles absent crossings and zero plateaus',()=>{
 assert.equal(stabiliserZeroTrim({...values,stabMaxValue:3,stabMinValue:1}),null);
 assert.equal(stabiliserZeroTrim({...values,stabMaxValue:1,stabMinValue:1}),null);
 assert.deepEqual(stabiliserZeroTrim({...values,stabMaxValue:0,stabMinValue:0}),{from:14,to:41});
 assert.deepEqual(stabiliserZeroTrim({...values,stabMaxValue:0}),{from:14,to:18});
 assert.deepEqual(stabiliserZeroTrim({...values,stabMinValue:0}),{from:41,to:41});
});
