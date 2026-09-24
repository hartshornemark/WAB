import test from"node:test";import assert from"node:assert/strict";import{validateAircraftC4}from"../src/domain/aircraft-c4";
const valid={datum:2.54,referenceArm:17.25,constantK:50,constantC:1000,macRcLength:4.193,lemacLerc:16.202};
test("C4 accepts the complete formula using decimal length values",()=>{assert.deepEqual(validateAircraftC4(valid),valid)});
test("C4 rejects zero C and MAC/RC length",()=>{assert.throws(()=>validateAircraftC4({...valid,constantC:0}),/C Constant/);assert.throws(()=>validateAircraftC4({...valid,macRcLength:0}),/MAC\/RC Length/)});
test("C4 requires a whole-number K Constant and permits a decimal C Constant",()=>{assert.throws(()=>validateAircraftC4({...valid,constantK:1.5}),/K Constant/);assert.equal(validateAircraftC4({...valid,constantC:2.5}).constantC,2.5)});
test("C4 rejects missing and non-finite values",()=>{assert.throws(()=>validateAircraftC4({...valid,referenceArm:""}),/Reference Arm/);assert.throws(()=>validateAircraftC4({...valid,lemacLerc:Infinity}),/LEMAC\/LERC/)});
test("C4 accepts Datum Zero and rejects a missing datum",()=>{assert.equal(validateAircraftC4({...valid,datum:0}).datum,0);assert.throws(()=>validateAircraftC4({...valid,datum:""}),/Datum/)});
