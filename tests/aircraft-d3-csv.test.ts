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
const legacyTemplate = `Group ID / Config,Position Name,Max Weight,Centroid,FWD,AFT,Index per wt unit,Fore-Aft Dimension (in)
AKE,11L,1587,14.026,13.259,14.793,-0.004476,
AKE,11R,1587,14.026,13.259,14.793,-0.004476,
PLA,11,3174,14.026,13.259,14.793,-0.004476,
PMC,11P,5102,14.479,13.259,15.698,-0.004385,`;
const geometry = { formula: { referenceArm: 20, constantC: 1000 }, lengthUnit: "M" };

test("D3 download uses explicit aircraft identity and hold routing",()=>assert.equal(aircraftD3CsvTemplate("321","P2F"),"Aircraft Type IATA,Series/Sub-Type,Deck ID,Hold ID,Hold Sub Code,Compartment ID,Bay ID,ULD ID / Config,Max Weight,Centroid,FWD,AFT,Index per wt unit,Fore-Aft Dimension (in)\n321,P2F,,,,,,,,,,,,\n"));
test("explicit routing assigns a Bay to its Deck, Hold Sub Code and Compartment",()=>{
  const csv=`${aircraftD3CsvTemplate("321","P2F").split("\n")[0]}\n321,P2F,LOWER,FWD,FLF,A,11,PAG,4626,20,19,21,0,125`;
  const result=parseAircraftD3Csv(csv,["A"],options,geometry,{holdId:"LOWER:FLF",deckName:"Lower Deck",typeCode:"321",subtype:"P2F"});
  assert.deepEqual(result.errors,[]);
  assert.equal(result.atomicBays[0].id,"11");
  assert.equal(result.atomicBays[0].compartmentId,"A");
});
test("optional aft sub-codes do not discard bays in the same saved D2 compartment",()=>{
  const header=aircraftD3CsvTemplate("310","300").split("\n")[0];
  const csv=`${header}
310,300,LOWER,AFT,ALF,4,41L,AKE,1588,30.171,29.404,30.938,0.00175,
310,300,LOWER,AFT,ALF,4,41R,AKE,1588,30.171,29.404,30.938,0.00175,
310,300,LOWER,AFT,ALM,4,42L,AKE,1588,31.753,30.986,32.520,0.00254,
310,300,LOWER,AFT,ALM,4,42R,AKE,1588,31.753,30.986,32.520,0.00254,
310,300,LOWER,AFT,ALA,4,43L,AKE,1588,33.334,32.567,34.101,0.00333,
310,300,LOWER,AFT,ALA,4,43R,AKE,1588,33.334,32.567,34.101,0.00333,`;
  const result=parseAircraftD3Csv(csv,["4"],options,geometry,{holdId:"LOWER:ALA",deckName:"Lower",typeCode:"310",subtype:"300"});
  assert.deepEqual(result.errors,[]);
  assert.deepEqual(result.atomicBays.map(bay=>bay.id),["41L","41R","42L","42R","43L","43R"]);
  assert.equal(result.sourceRowCount,6);
  assert.equal(result.matchedRowCount,6);
});
test("D3 blocks a CSV for another aircraft",()=>{const csv=`${aircraftD3CsvTemplate("310","300").split("\n")[0]}\n310,300,LOWER,FWD,FLF,A,11,PAG,4626,20,19,21,0,125`;assert.match(parseAircraftD3Csv(csv,["A"],options,geometry,{holdId:"LOWER:FLF",typeCode:"359",subtype:"900"}).errors.join(" "),/does not match the open aircraft/)});

test("AHM565 CSV derives atomic bays and overlapping loading footprints", () => {
  const result = parseAircraftD3Csv(legacyTemplate, ["1"], options);
  assert.deepEqual(result.errors, []);
  assert.deepEqual(result.atomicBays.map(bay => bay.id), ["11L", "11R"]);
  assert.equal(result.rows.length, 4);
  assert.deepEqual(result.rows.find(row => row.positionId === "11P" && row.uldCode === "PMC")?.occupiedBayIds, ["11L", "11R"]);
  assert.equal(result.rows[0].compartmentId, "1");
});

test("different ULD codes at the same position remain separate lock arrangements", () => {
  const csv = `${legacyTemplate}\nPAG,11P,5102,14.326,13.106,15.545,-0.004412`;
  const result = parseAircraftD3Csv(csv, ["1"], options);
  assert.deepEqual(result.errors, []);
  const arrangements = result.rows.filter(row => row.positionId === "11P" && row.uldType === "LD7");
  assert.equal(arrangements.length, 2);
  assert.deepEqual(arrangements.map(row => row.uldCode).sort(), ["PAG", "PMC"]);
  assert.notEqual(arrangements[0].balanceCentroid, arrangements[1].balanceCentroid);
});

test("AHM565 CSV expands combined position names and filters to the selected hold compartments", () => {
  const csv = `${legacyTemplate}\nAKE,12L;12R,1587,15.609,14.842,16.376,-0.004159\nAKE,31L,1587,41.253,40.486,42.020,0.000969`;
  const result = parseAircraftD3Csv(csv, ["1"], options);
  assert.deepEqual(result.errors, []);
  assert.ok(result.atomicBays.some(bay => bay.id === "12L"));
  assert.ok(result.atomicBays.some(bay => bay.id === "12R"));
  assert.ok(!result.rows.some(row => row.positionId === "31L"));
});

test("AHM565 CSV reports a recognised ULD code not selected on B5", () => {
  const unavailable = options.map(option => ({ ...option, adopted: option.code !== "PMC" }));
  const result = parseAircraftD3Csv(legacyTemplate, ["1"], unavailable);
  assert.ok(result.errors.some(error => error.includes("PMC") && error.includes("B5")));
});

test("the same ULD code cannot appear twice with different lock limits", () => {
  const csv = `${legacyTemplate}\nPMC,11P,5102,14.000,13.000,15.000,-0.004500`;
  const result = parseAircraftD3Csv(csv, ["1"], options);
  assert.ok(result.errors.some(error => error.includes("11P / PMC") && error.includes("different limits")));
});

test("index-only single positions derive their geometry without L/R suffixes", () => {
  const csv = "Group ID / Config,Position Name,Max Weight,Index per wt unit\nAKE,11,1587,-0.01\nAKE,12,1587,-0.008";
  const result = parseAircraftD3Csv(csv, ["1"], options, geometry);
  assert.deepEqual(result.errors, []);
  assert.deepEqual(result.atomicBays.map(b => b.id), ["11", "12"]);
  assert.equal(result.rows[0].balanceCentroid, 10);
  assert.equal(result.rows[0].balanceFrom, 9.23292);
  assert.equal(result.rows[0].balanceTo, 10.76708);
  assert.deepEqual(result.rows[0].occupiedBayIds, ["11"]);
});
test("CSV coordinates win, and only blank fields are calculated", () => {
  const csv = "Group ID / Config,Position Name,Max Weight,Centroid,FWD,AFT,Index per wt unit\nAKE,11,1587,11,10,,-0.01";
  const result = parseAircraftD3Csv(csv, ["1"], options, geometry);
  assert.deepEqual(result.errors, []);
  assert.equal(result.rows[0].balanceCentroid, 11);
  assert.equal(result.rows[0].balanceFrom, 10);
  assert.equal(result.rows[0].balanceTo, 11.76708);
});
test("derived footprints convert inches into the aircraft length unit", () => {
  for (const [unit, factor] of [["IN",1],["CM",2.54],["FT",1/12]] as const) {
    const result = parseAircraftD3Csv("Group ID / Config,Position Name,Max Weight,Index per wt unit\nAKE,11,1587,0", ["1"], options, {...geometry,lengthUnit:unit});
    assert.deepEqual(result.errors, []);
    assert.ok(Math.abs(result.rows[0].balanceTo! - (20+30.2*factor)) < 0.000001);
  }
});
test("alphabetic compartments accept single freighter positions", () => {
  const result = parseAircraftD3Csv("Group ID / Config,Position Name,Max Weight,Index per wt unit\nPAG,A1,4626,0", ["A"], options, geometry);
  assert.deepEqual(result.errors, []);
  assert.equal(result.atomicBays[0].id, "A1");
});
test("missing derivation inputs and malformed supplied values block import", () => {
  const csv = "Group ID / Config,Position Name,Max Weight,Centroid,FWD,AFT,Index per wt unit\nAKE,11,1587,,,,0";
  assert.ok(parseAircraftD3Csv(csv,["1"],options).errors.some(e=>e.includes("C4")));
  assert.ok(parseAircraftD3Csv(csv.replace(",,,,0",",oops,,,0"),["1"],options,geometry).errors.some(e=>e.includes("Centroid must be a number")));
});

const orientedHeader = "Group ID / Config,Position Name,Max Weight,Centroid,FWD,AFT,Index per wt unit,Fore-Aft Dimension (in)";
test("optional running dimension overrides only missing limits", () => {
  const derived = parseAircraftD3Csv(`${orientedHeader}\nPAG,A1,4626,,,,0,125`,["A"],options,geometry);
  assert.deepEqual(derived.errors, []);
  assert.equal(derived.rows[0].balanceFrom,18.4125);
  assert.equal(derived.rows[0].balanceTo,21.5875);
  const supplied = parseAircraftD3Csv(`${orientedHeader}\nPAG,A1,4626,20,19,21,0,125`,["A"],options,geometry);
  assert.deepEqual(supplied.errors, []);
  assert.equal(supplied.rows[0].balanceFrom,19);
  assert.equal(supplied.rows[0].balanceTo,21);
  const partial = parseAircraftD3Csv(`${orientedHeader}\nPAG,A1,4626,20,19,,0,125`,["A"],options,geometry);
  assert.deepEqual(partial.errors, []);
  assert.equal(partial.rows[0].balanceFrom,19);
  assert.equal(partial.rows[0].balanceTo,21.5875);
});
test("blank running dimension retains the ULD default", () => {
  const result = parseAircraftD3Csv(`${orientedHeader}\nPAG,A1,4626,,,,0,`,["A"],options,geometry);
  assert.deepEqual(result.errors, []);
  assert.equal(result.rows[0].balanceFrom,18.8824);
  assert.equal(result.rows[0].balanceTo,21.1176);
});
test("invalid running dimensions never silently use the default", () => {
  for(const dimension of ["0","-88","oops","Infinity"]){
    const result=parseAircraftD3Csv(`${orientedHeader}\nPAG,A1,4626,,,,0,${dimension}`,["A"],options,geometry);
    assert.ok(result.errors.some(error=>error.includes("Fore-Aft Dimension (in)")));
  }
});
