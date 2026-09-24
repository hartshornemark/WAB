import test from "node:test";
import assert from "node:assert/strict";
import { indexForMacPercent, macPercentForIndex } from "../src/domain/aircraft-balance-formula";

const formula={datum:2.54,referenceArm:17.25,constantK:50,constantC:1000,macRcLength:4.193,lemacLerc:16.202};

test("C4 formula reproduces saved C5.1 MAC values",()=>{
  assert.equal(macPercentForIndex(35400,41.30,formula).toFixed(2),"19.13");
  assert.equal(macPercentForIndex(58500,49.00,formula).toFixed(2),"24.59");
});

test("MAC and Index conversions are reversible",()=>{
  const index=indexForMacPercent(62500,36.32,formula);
  assert.ok(Math.abs(macPercentForIndex(62500,index,formula)-36.32)<1e-10);
});
