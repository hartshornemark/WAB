import test from "node:test";
import assert from "node:assert/strict";
import {formatNumeric} from "../src/domain/display-standards";

test("ordinary Index follows the carrier display preference",()=>{
  assert.equal(formatNumeric(51.126,"index",1),"51.1");
  assert.equal(formatNumeric(51.126,"index",2),"51.13");
  assert.equal(formatNumeric("index",51.126,2),"51.13");
});

test("Index Per Weight Unit remains fixed at five decimal places",()=>{
  assert.equal(formatNumeric(0.009724,"indexPerWeightUnit",1),"0.00972");
  assert.equal(formatNumeric(0.009724,"indexPerWeightUnit",2),"0.00972");
});
