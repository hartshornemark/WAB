import test from "node:test";
import assert from "node:assert/strict";
import {
  AircraftD6Invalid,
  validateD6Section,
  type AircraftD6Snapshot,
  type GalleyLocation,
  type WaterLocation,
} from "../src/domain/aircraft-d6";
import {
  aircraftD6Status,
  d6SectionStatus,
  galleyLocationComplete,
  waterLocationComplete,
} from "../src/domain/aircraft-d6-status";
import { balanceArmFromIndexPerWeightUnit } from "../src/domain/index-per-weight-unit";

const formula = { referenceArm: 18.85, constantC: 838.7 };
const waterIndex = 0.0108;
const galleyIndex = -0.01061;
const water: WaterLocation = {
  id: "XPW",
  name: "Potable Water",
  maxWeight: 200,
  centroid: balanceArmFromIndexPerWeightUnit(waterIndex, formula),
  index: waterIndex,
};
const galley: GalleyLocation = {
  id: "XG1",
  description: "Galley 1",
  maxWeight: 700,
  centroid: balanceArmFromIndexPerWeightUnit(galleyIndex, formula),
  index: galleyIndex,
};
const snap: AircraftD6Snapshot = {
  canView: true,
  canEdit: true,
  revision: "r",
  typeCode: "319",
  subtype: "100",
  waterApplicable: true,
  galleyApplicable: true,
  waterLocations: [water],
  galleyLocations: [galley],
  balanceFormula: formula,
};
const validate = (section: "waterLocations" | "galleyLocations", rows: unknown) =>
  validateD6Section(section, rows, formula);

test("D6 configures when both sections have one complete row", () =>
  assert.equal(aircraftD6Status(snap), "configured"));
test("D6 is partial when only one section is complete", () =>
  assert.equal(aircraftD6Status({ ...snap, galleyLocations: [] }), "partial"));
test("D6 section is incomplete without rows", () =>
  assert.equal(d6SectionStatus(true, [], waterLocationComplete), "incomplete"));

test("D6 marks an unchecked section Not Active", () =>
  assert.equal(d6SectionStatus(false, [], waterLocationComplete), "not_active"));
test("D6 keeps an unreviewed section incomplete", () => {
  assert.equal(d6SectionStatus(null, [], waterLocationComplete), "incomplete");
  assert.equal(aircraftD6Status({ ...snap, waterApplicable: null }), "partial");
});
test("D6 configures when both reviewed sections are inactive", () =>
  assert.equal(aircraftD6Status({
    ...snap, waterApplicable: false, galleyApplicable: false,
    waterLocations: [], galleyLocations: [],
  }), "configured"));

test("D6 requires positive maximum weight", () =>
  assert.throws(
    () => validate("waterLocations", [{ ...water, maxWeight: 0 }]),
    AircraftD6Invalid,
  ));
test("D6 limits short codes to three alphanumerics", () =>
  assert.throws(
    () => validate("galleyLocations", [{ ...galley, id: "X-G1" }]),
    AircraftD6Invalid,
  ));
test("D6 accepts three-character short codes", () => {
  assert.equal(validate("waterLocations", [{ ...water, id: "XPW" }])[0].id, "XPW");
  assert.equal(validate("galleyLocations", [{ ...galley, id: "XG1" }])[0].id, "XG1");
});
test("D6 calculates potable water Centroid from Index Per Weight Unit", () => {
  const [validated] = validate("waterLocations", [
    { ...water, centroid: 999, index: "0.01080" },
  ]);
  assert.equal(validated.centroid, 27.90796);
  assert.equal(validated.index, 0.0108);
});
test("D6 calculates galley Centroid from Index Per Weight Unit", () => {
  const [validated] = validate("galleyLocations", [
    { ...galley, centroid: null, index: "-0.01061" },
  ]);
  assert.equal(validated.centroid, 9.951393);
  assert.equal(validated.index, -0.01061);
});
test("D6 requires C4 to calculate Balance Arm Centroid", () =>
  assert.throws(
    () => validateD6Section("waterLocations", [water]),
    /configure C4/,
  ));
test("D6 complete predicates accept valid rows", () => {
  assert.equal(waterLocationComplete(water), true);
  assert.equal(galleyLocationComplete(galley), true);
});
