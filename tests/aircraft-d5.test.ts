import test from "node:test";
import assert from "node:assert/strict";
import {
  AircraftD5Invalid,
  validateExcludedRowsAgainstCabinAreas,
  validateD5Section,
  type AircraftD5Snapshot,
  type CabinArea,
  type CrewLocation,
} from "../src/domain/aircraft-d5";
import {
  aircraftD5Status,
  d5SectionStatus,
  cabinAreaComplete,
  crewLocationComplete,
} from "../src/domain/aircraft-d5-status";
import { balanceArmFromIndexPerWeightUnit } from "../src/domain/index-per-weight-unit";

const formula = { referenceArm: 18.85, constantC: 838.7 };
const areaIndex = -0.00879;
const locationIndex = -0.01641;
const area: CabinArea = {
  id: "0A",
  deck: "CABIN",
  startRow: 1,
  endRow: 4,
  centroid: balanceArmFromIndexPerWeightUnit(areaIndex, formula),
  startArm: 9.462,
  endArm: 14.034,
  index: areaIndex,
};
const location: CrewLocation = {
  id: "XFD",
  description: "Flight Deck Pilot Seats",
  seats: 2,
  centroid: balanceArmFromIndexPerWeightUnit(locationIndex, formula),
  index: locationIndex,
};
const snap: AircraftD5Snapshot = {
  canView: true,
  canEdit: true,
  revision: "r",
  typeCode: "319",
  subtype: "100",
  excludedRows: [],
  cabinAreas: [area],
  flightDeckLocations: [location],
  cabinCrewLocations: [location],
};
const validate = (section: Parameters<typeof validateD5Section>[0], rows: unknown) =>
  validateD5Section(section, rows, formula) as any[];

test("D5 configures when every section has one complete row", () =>
  assert.equal(aircraftD5Status(snap), "configured"));
test("D5 is partial when one section has no row", () =>
  assert.equal(aircraftD5Status({ ...snap, cabinCrewLocations: [] }), "partial"));
test("D5 section is incomplete with no rows", () =>
  assert.equal(d5SectionStatus([], crewLocationComplete), "incomplete"));
test("D5 validates cabin balance arm order", () =>
  assert.throws(() => validate("cabinAreas", [{ ...area, startArm: 20 }]), AircraftD5Invalid));
test("D5 requires positive whole seat counts", () =>
  assert.throws(
    () => validate("flightDeckLocations", [{ ...location, seats: 1.5 }]),
    AircraftD5Invalid,
  ));
test("D5 permits three-character Flight Deck and Cabin Crew Location IDs", () => {
  assert.equal(validate("flightDeckLocations", [{ ...location, id: "XFD" }])[0].id, "XFD");
  assert.equal(validate("cabinCrewLocations", [{ ...location, id: "XLA" }])[0].id, "XLA");
});
test("D5 complete row predicates accept valid values", () => {
  assert.equal(cabinAreaComplete(area), true);
  assert.equal(crewLocationComplete(location), true);
});
test("D5 calculates Cabin Definition Centroid from Index Per Weight Unit", () => {
  const [validated] = validate("cabinAreas", [
    { ...area, centroid: 999, index: "-0.00972", startArm: null, endArm: null },
  ]);
  assert.equal(validated.centroid, 10.697836);
  assert.equal(validated.index, -0.00972);
});
test("D5 calculates Flight Deck Centroid from Index Per Weight Unit", () => {
  const [validated] = validate("flightDeckLocations", [
    { ...location, centroid: 999, index: "-0.01217" },
  ]);
  assert.equal(validated.centroid, 8.643021);
  assert.equal(validated.index, -0.01217);
});
test("D5 calculates Cabin Crew Centroid from Index Per Weight Unit", () => {
  const [validated] = validate("cabinCrewLocations", [
    { ...location, id: "XLA", centroid: null, index: "-0.01000" },
  ]);
  assert.equal(validated.centroid, 10.463);
  assert.equal(validated.index, -0.01);
});
test("D5 requires Index Per Weight Unit even when a Centroid is supplied", () =>
  assert.throws(
    () => validate("cabinAreas", [{ ...area, centroid: 10.7, index: null }]),
    /enter Index per Weight Unit/,
  ));
test("D5 requires C4 to calculate Centroid", () =>
  assert.throws(
    () => validateD5Section("cabinAreas", [{ ...area, centroid: null, index: -0.00972 }]),
    /configure C4/,
  ));
test("D5 requires C4 to calculate Flight Deck Centroid", () =>
  assert.throws(
    () => validateD5Section("flightDeckLocations", [{ ...location, centroid: null }]),
    /configure C4/,
  ));
test("D5 accepts decimal text for optional Balance Arm boundaries", () => {
  const [validated] = validate("cabinAreas", [
    { ...area, startArm: "9.462", endArm: "14.034", index: "-0.00879" },
  ]) as CabinArea[];
  assert.equal(validated.startArm, 9.462);
  assert.equal(validated.endArm, 14.034);
});
test("D5 permits deliberate gaps between cabin row ranges", () =>
  assert.doesNotThrow(() =>
    validate("cabinAreas", [
      { ...area, id: "A", startRow: 1, endRow: 6 },
      { ...area, id: "B", startRow: 8, endRow: 15 },
    ]),
  ));
test("D5 accepts unique excluded row numbers and sorts them",()=>
  assert.deepEqual(validate("excludedRows",[13,7]),[7,13]));
test("D5 requires excluded rows to belong to a cabin area",()=>
  assert.throws(()=>validateExcludedRowsAgainstCabinAreas([13],[area]),/outside every Cabin Area/));
test("D5 permits an internal excluded row while retaining one Cabin Area",()=>
  assert.doesNotThrow(()=>validateExcludedRowsAgainstCabinAreas([3],[area])));
test("D5 prevents excluding every row in a Cabin Area",()=>
  assert.throws(()=>validateExcludedRowsAgainstCabinAreas([1,2,3,4],[area]),/retain at least one row/));
test("D5 rejects overlapping cabin row ranges", () =>
  assert.throws(
    () =>
      validate("cabinAreas", [
        { ...area, id: "A", startRow: 1, endRow: 6 },
        { ...area, id: "B", startRow: 6, endRow: 15 },
      ]),
    AircraftD5Invalid,
  ));
test("D5 permits both optional Balance Arm boundaries to remain blank", () => {
  const optional = { ...area, startArm: null, endArm: null };
  assert.doesNotThrow(() => validate("cabinAreas", [optional]));
  assert.equal(cabinAreaComplete(optional), true);
});
test("D5 requires optional Balance Arm boundaries as a pair", () =>
  assert.throws(
    () => validate("cabinAreas", [{ ...area, startArm: 9, endArm: null }]),
    /both Balance Arm From and To/,
  ));
