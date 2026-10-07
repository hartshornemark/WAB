import test from "node:test";
import assert from "node:assert/strict";
import {integerAxisScale} from "../src/domain/chart-axis";

test("rounds chart limits outward and produces evenly spaced integer ticks",()=>{
  assert.deepEqual(integerAxisScale(-20.1,39.1),{
    min:-21,
    max:43,
    ticks:[-21,-5,11,27,43],
  });
});

test("keeps a useful integer range when all chart values are the same",()=>{
  assert.deepEqual(integerAxisScale(7,7),{
    min:7,
    max:11,
    ticks:[7,8,9,10,11],
  });
});

test("normalises reversed inputs and interval counts",()=>{
  assert.deepEqual(integerAxisScale(5.2,-2.2,3),{
    min:-3,
    max:6,
    ticks:[-3,0,3,6],
  });
});
