import test from "node:test";
import assert from "node:assert/strict";
import { calculateFuelScheduleEffect } from "../src/domain/aircraft-c8-schedule-effect";
import type { FuelLoadingSchedule, NonStandardFuelTank } from "../src/domain/aircraft-c8";

const formula = { datum: 0, referenceArm: 0, constantK: 0, constantC: 100, macRcLength: 1, lemacLerc: 0 };
const tank = (tankShortCode: string, arms: [number, number]): NonStandardFuelTank => ({
  tankName: tankShortCode,
  tankShortCode,
  maximumVolume: 1000,
  sourceSpecificGravity: 0.8,
  indexPerUnitWeight: null,
  weights: [],
  points: [
    { volume: 0, balanceArm: arms[0], importedWeight: null, importedIndex: null },
    { volume: 1000, balanceArm: arms[1], importedWeight: null, importedIndex: null },
  ],
});
const schedule = (quantityBasis: "VOLUME" | "WEIGHT", steps: FuelLoadingSchedule["steps"]): FuelLoadingSchedule => ({ name: "Test", specificGravity: 0.8, quantityBasis, steps });

test("calculates the cumulative index and arm from an interpolated tank curve", () => {
  const result = calculateFuelScheduleEffect(schedule("VOLUME", [
    { amount: 500, tankCodes: ["XTI"] },
    { amount: 500, tankCodes: ["XTI"] },
  ]), [tank("XTI", [10, 20])], formula);
  assert.equal(result.error, null);
  assert.deepEqual(result.points, [
    { step: 1, weight: 400, indexValue: 60, balanceArm: 15 },
    { step: 2, weight: 800, indexValue: 160, balanceArm: 20 },
  ]);
});

test("combines loaded tanks into one cumulative fuel result", () => {
  const result = calculateFuelScheduleEffect(schedule("VOLUME", [
    { amount: 500, tankCodes: ["XTI"] },
    { amount: 500, tankCodes: ["XTT"] },
  ]), [tank("XTI", [10, 10]), tank("XTT", [30, 30])], formula);
  assert.equal(result.error, null);
  assert.deepEqual(result.points.at(-1), { step: 2, weight: 800, indexValue: 160, balanceArm: 20 });
});

test("converts a weight-based schedule to tank volume", () => {
  const result = calculateFuelScheduleEffect(schedule("WEIGHT", [
    { amount: 400, tankCodes: ["XTI"] },
  ]), [tank("XTI", [10, 20])], formula);
  assert.equal(result.error, null);
  assert.deepEqual(result.points[0], { step: 1, weight: 400, indexValue: 60, balanceArm: 15 });
});

test("does not invent an allocation when a step selects multiple tank identities", () => {
  const result = calculateFuelScheduleEffect(schedule("VOLUME", [
    { amount: 500, tankCodes: ["XTI", "XTT"] },
  ]), [tank("XTI", [10, 20]), tank("XTT", [30, 30])], formula);
  assert.match(result.error ?? "", /one tank identity/);
  assert.deepEqual(result.points, []);
});

test("reports when a tank curve does not cover the loaded volume", () => {
  const result = calculateFuelScheduleEffect(schedule("VOLUME", [
    { amount: 1100, tankCodes: ["XTI"] },
  ]), [{ ...tank("XTI", [10, 20]), maximumVolume: null }], formula);
  assert.match(result.error ?? "", /curve does not cover/);
});

test("caps a one-unit published-schedule rounding excess at the tank maximum", () => {
  const result = calculateFuelScheduleEffect(schedule("VOLUME", [
    { amount: 500, tankCodes: ["XTI"] },
    { amount: 501, tankCodes: ["XTI"] },
  ]), [tank("XTI", [10, 20])], formula);
  assert.equal(result.error, null);
  assert.deepEqual(result.points.at(-1), { step: 2, weight: 800, indexValue: 160, balanceArm: 20 });
});

test("still rejects a tank-volume excess greater than one unit", () => {
  const result = calculateFuelScheduleEffect(schedule("VOLUME", [
    { amount: 1002, tankCodes: ["XTI"] },
  ]), [tank("XTI", [10, 20])], formula);
  assert.match(result.error ?? "", /exceeds the maximum Volume/);
  assert.deepEqual(result.points, []);
});
