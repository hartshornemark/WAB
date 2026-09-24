import test from"node:test";import assert from"node:assert/strict";import{validateAircraftC11}from"../src/domain/aircraft-c11";import{aircraftC11Status}from"../src/domain/aircraft-c11-status";
const values={macFwdLimit:14,macAftLimit:41,stabMaxValue:3.5,stabMinValue:-3,variationFwd:18,variationAft:41,rateOfChange:-0.282608695652174};
test("accepts a variation range contained by the MAC limits",()=>assert.deepEqual(validateAircraftC11(values),{macFwdLimit:14,macAftLimit:41,stabMaxValue:3.5,stabMinValue:-3,variationFwd:18,variationAft:41}));
test("accepts signed decimal stabiliser values entered as text",()=>assert.deepEqual(validateAircraftC11({...values,stabMaxValue:"2.5",stabMinValue:"-2.5"}),{macFwdLimit:14,macAftLimit:41,stabMaxValue:2.5,stabMinValue:-2.5,variationFwd:18,variationAft:41}));
test("rejects a reversed variation range",()=>assert.throws(()=>validateAircraftC11({...values,variationFwd:42}),/variation range/));
test("marks a complete stored C11.1 record configured",()=>assert.equal(aircraftC11Status({canView:true,canEdit:true,exists:true,revision:"r",typeCode:"319",subtype:"100",values}),"configured"));
test("marks a missing C11.1 record incomplete",()=>assert.equal(aircraftC11Status({canView:true,canEdit:true,exists:false,revision:"",typeCode:"319",subtype:"100",values}),"incomplete"));
