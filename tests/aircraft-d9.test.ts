import test from "node:test";
import assert from "node:assert/strict";
import {
  AircraftD9Invalid,
  buildD9Rows,
  deriveD9ClassSummaries,
  suggestD9Description,
  spillD9ClassSeats,
  validateD9Configuration,
  type AircraftD9Snapshot,
  type D9AreaRow,
  type D9Class,
} from "../src/domain/aircraft-d9";
import { aircraftD9Status, d9ConfigurationStatuses } from "../src/domain/aircraft-d9-status";

const areas = [
  { id: "0A", rowFrom: 1, rowTo: 4, centroid: 11, from: 9, to: 14, index: -0.005 },
  { id: "0B", rowFrom: 5, rowTo: 7, centroid: 18, from: 17, to: 20, index: 0.001 },
];
const classes: D9Class[] = [
  { code: "F", name: "First", slot: 1 },
  { code: "C", name: "Business", slot: 2 },
  { code: "W", name: "Premium", slot: 3 },
  { code: "Y", name: "Economy", slot: 4 },
];
const formula = { referenceArm: 17.25, constantC: 1000 };
const row = (areaId: string, seats: [number, number, number, number], totalSeats: number): D9AreaRow => ({
  areaId,
  classSeats: seats,
  totalSeats,
  centroid: areaId === "0A" ? 11 : 18,
  from: areaId === "0A" ? 9 : 17,
  to: areaId === "0A" ? 14 : 20,
  index: areaId === "0A" ? -0.005 : 0.001,
});
const configuration = {
  code: "A",
  description: "C44",
  rows: [row("0A", [0, 16, 0, 0], 16), row("0B", [0, 12, 0, 0], 12)],
};
const snapshot: AircraftD9Snapshot = {
  canView: true,
  canEdit: true,
  revision: "r",
  typeCode: "319",
  subtype: "100",
  excludedRows: [],
  cabinAreas: areas,
  classes,
  configurations: [configuration],
};

test("D9 configures when every D5 area is complete and totals match", () => {
  assert.equal(aircraftD9Status(snapshot, formula), "configured");
});

test("D9 cabin section is partial when a D5 area is missing", () => {
  assert.equal(d9ConfigurationStatuses({ ...configuration, rows: [configuration.rows[0]] }, areas, classes, formula).page, "partial");
});

test("D9 derives class rows from the outer limits and C4 formula", () => {
  const summary = deriveD9ClassSummaries(configuration, areas, classes, formula)[0];
  assert.deepEqual(
    [summary.code, summary.firstRow, summary.lastRow, summary.totalSeats, summary.from, summary.to, summary.centroid],
    ["C", 1, 7, 28, 9, 20, 14.5],
  );
  assert.equal(summary.index, -0.00275);
});

test("D9 uses the first and last available rows after D5 exclusions", () => {
  const summary = deriveD9ClassSummaries(configuration, areas, classes, formula, [1, 7])[0];
  assert.deepEqual([summary.firstRow, summary.lastRow], [2, 6]);
});

test("D9 calculates Total Seats and Balance Arm Centroid", () => {
  const result = validateD9Configuration(
    {
      ...configuration,
      rows: configuration.rows.map((value) => ({ ...value, totalSeats: 999, centroid: 999 })),
    },
    areas,
    classes,
    formula,
  );
  assert.deepEqual(result.rows.map((value) => value.totalSeats), [16, 12]);
  assert.deepEqual(result.rows.map((value) => value.centroid), [12.25, 18.25]);
});

test("D9 requires one alphabetic configuration code", () => {
  assert.equal(validateD9Configuration({ ...configuration, code: "y" }, areas, classes, formula).code, "Y");
  assert.throws(
    () => validateD9Configuration({ ...configuration, code: "Y100" }, areas, classes, formula),
    AircraftD9Invalid,
  );
});

test("D9 suggests its description from class codes and configuration-wide seat totals", () => {
  assert.equal(suggestD9Description(configuration.rows, classes), "C28");
  const oneClass: D9Class[] = [
    { code: "Y", name: "Economy Class", slot: 1 },
    { code: null, name: null, slot: 2 },
    { code: null, name: null, slot: 3 },
    { code: null, name: null, slot: 4 },
  ];
  assert.equal(suggestD9Description([
    { classSeats: [36, 0, 0, 0] },
    { classSeats: [48, 0, 0, 0] },
  ], oneClass), "Y84");
});

test("D9 spills the cabin-area seat balance into the next defined class",()=>{
 assert.deepEqual(spillD9ClassSeats([null,null,null,null],1,"16",[2,4],16),[null,"16",null,0]);
 assert.deepEqual(spillD9ClassSeats([null,null,null,null],1,"6",[2,4],16),[null,"6",null,10]);
});

test("D9 spillover follows defined class order and preserves earlier allocations",()=>{
 assert.deepEqual(spillD9ClassSeats([4,null,null,null],1,"8",[1,2,4],16),[4,"8",null,4]);
 assert.deepEqual(spillD9ClassSeats([4,8,null,4],1,"",[1,2,4],16),[4,"",null,null]);
});

test("D9 spillover continues through all four defined classes",()=>{
 const afterFirst=spillD9ClassSeats([null,null,null,null],0,"4",[1,2,3,4],20);
 assert.deepEqual(afterFirst,["4",16,0,0]);
 const afterBusiness=spillD9ClassSeats(afterFirst,1,"6",[1,2,3,4],20);
 assert.deepEqual(afterBusiness,["4","6",10,0]);
 const afterPremium=spillD9ClassSeats(afterBusiness,2,"3",[1,2,3,4],20);
 assert.deepEqual(afterPremium,["4","6","3",7]);
});

test("D9 permits optional Balance Arm From and To without reducing completion", () => {
  const value = {
    ...configuration,
    rows: configuration.rows.map(rowValue => ({ ...rowValue, from:null, to:null })),
  };
  const result = validateD9Configuration(value, areas, classes, formula);
  assert.deepEqual(result.rows.map(rowValue => [rowValue.from,rowValue.to]), [[null,null],[null,null]]);
  assert.equal(d9ConfigurationStatuses(result,areas,classes,formula).page,"configured");
});

test("D9 disables undefined classes and excludes their values from Total Seats", () => {
  const oneClass: D9Class[] = [
    { code: "Y", name: "Economy Class", slot: 1 },
    { code: null, name: null, slot: 2 },
    { code: null, name: null, slot: 3 },
    { code: null, name: null, slot: 4 },
  ];
  const result = validateD9Configuration(
    {
      code: "A",
      description: "Y180",
      rows: [
        { ...configuration.rows[0], classSeats: [36, 90, 80, 70], index: -0.005 },
        { ...configuration.rows[1], classSeats: [48, 90, 80, 70], index: 0.001 },
      ],
    },
    areas,
    oneClass,
    formula,
  );
  assert.deepEqual(result.rows[0].classSeats, [36, 0, 0, 0]);
  assert.equal(result.rows[0].totalSeats, 36);
});

test("D9 requires the C4 formula before calculating Balance Arm Centroid", () => {
  assert.throws(() => validateD9Configuration(configuration, areas, classes, null), AircraftD9Invalid);
});

test("D9 builds missing cabin rows from D5 values", () => {
  assert.deepEqual(
    buildD9Rows(areas, []).map((value) => [value.areaId, value.centroid, value.from, value.to]),
    [["0A", 11, 9, 14], ["0B", 18, 17, 20]],
  );
});

test("D9 requires one complete class summary", () => {
  assert.equal(d9ConfigurationStatuses({ ...configuration, rows: [row("0A", [0, 0, 0, 0], 1)] }, areas, classes, formula).classInfo, "incomplete");
});
test("D9 is not required for a Freighter",()=>assert.equal(aircraftD9Status({...snapshot,configurations:[]},formula,"FREIGHTER"),"not_required"));

test("D9 class endpoints follow physical row sequence rather than numeric order",()=>{
 const summaries=deriveD9ClassSummaries({...configuration,rows:[row("0A",[0,20,0,0],20)]},[{...areas[0],rowTo:13,rowSequence:[13,1,2,3,4]}],classes,formula);
 assert.equal(summaries[0].firstRow,13);assert.equal(summaries[0].lastRow,4);assert.equal(summaries[0].totalSeats,20);
});
