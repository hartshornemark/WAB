import test from "node:test";
import assert from "node:assert/strict";
import { aircraftD3CsvTemplate, parseAircraftD3Csv } from "../src/domain/aircraft-d3-csv";

const options = [
  { code: "AKE", type: "LD3", baseCode: "K", baseWidth: 61.5, baseLength: 60.4, adopted: true },
  { code: "PKC", type: "LD3", baseCode: "K", baseWidth: 61.5, baseLength: 60.4, adopted: true },
  { code: "PLA", type: "LD8", baseCode: "L", baseWidth: 125, baseLength: 60.4, adopted: true },
  { code: "PAG", type: "LD7", baseCode: "6", baseWidth: 125, baseLength: 88, adopted: true },
  { code: "PMC", type: "LD7", baseCode: "6", baseWidth: 125, baseLength: 96, adopted: true },
];

test("AHM565 CSV derives atomic bays and overlapping loading footprints", () => {
  const result = parseAircraftD3Csv(aircraftD3CsvTemplate, ["1"], options);
  assert.deepEqual(result.errors, []);
  assert.deepEqual(result.atomicBays.map(bay => bay.id), ["11L", "11R"]);
  assert.equal(result.rows.length, 4);
  assert.deepEqual(result.rows.find(row => row.positionId === "11P" && row.uldCode === "PMC")?.occupiedBayIds, ["11L", "11R"]);
  assert.equal(result.rows[0].compartmentId, "1");
});

test("different ULD codes at the same position remain separate lock arrangements", () => {
  const csv = `${aircraftD3CsvTemplate}\nPAG,11P,5102,14.326,13.106,15.545,-0.004412`;
  const result = parseAircraftD3Csv(csv, ["1"], options);
  assert.deepEqual(result.errors, []);
  const arrangements = result.rows.filter(row => row.positionId === "11P" && row.uldType === "LD7");
  assert.equal(arrangements.length, 2);
  assert.deepEqual(arrangements.map(row => row.uldCode).sort(), ["PAG", "PMC"]);
  assert.notEqual(arrangements[0].balanceCentroid, arrangements[1].balanceCentroid);
});

test("AHM565 CSV expands combined position names and filters to the selected hold compartments", () => {
  const csv = `${aircraftD3CsvTemplate}\nAKE,12L;12R,1587,15.609,14.842,16.376,-0.004159\nAKE,31L,1587,41.253,40.486,42.020,0.000969`;
  const result = parseAircraftD3Csv(csv, ["1"], options);
  assert.deepEqual(result.errors, []);
  assert.ok(result.atomicBays.some(bay => bay.id === "12L"));
  assert.ok(result.atomicBays.some(bay => bay.id === "12R"));
  assert.ok(!result.rows.some(row => row.positionId === "31L"));
});

test("AHM565 CSV reports a recognised ULD code not selected on B5", () => {
  const unavailable = options.map(option => ({ ...option, adopted: option.code !== "PMC" }));
  const result = parseAircraftD3Csv(aircraftD3CsvTemplate, ["1"], unavailable);
  assert.ok(result.errors.some(error => error.includes("PMC") && error.includes("B5")));
});

test("the same ULD code cannot appear twice with different lock limits", () => {
  const csv = `${aircraftD3CsvTemplate}\nPMC,11P,5102,14.000,13.000,15.000,-0.004500`;
  const result = parseAircraftD3Csv(csv, ["1"], options);
  assert.ok(result.errors.some(error => error.includes("11P / PMC") && error.includes("different limits")));
});
