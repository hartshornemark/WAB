import test from "node:test";
import assert from "node:assert/strict";
import { aircraftD2CsvTemplate, parseAircraftD2Csv } from "../src/domain/aircraft-d2-csv";

const decks = [{ code: "LOWER", name: "Lower Deck" }, { code: "MAIN", name: "Main Deck" }];
const heading = "Aircraft Type IATA,Series/Sub-Type,Deck ID,Hold Type,Hold ID,Hold Sub Code,Compartment ID,Area ID,MAXWT,VOL,BA Centroid,BA FWD,BA AFT,Index Per Weight Unit,Door";
const row = (values:string, typeCode="310", subtype="300", door="Y") => `${typeCode},${subtype},${values},${door}`;
const csv = (...rows:string[]) => `${heading}\n${rows.join("\n")}`;
const expected = {typeCode:"310",subtype:"300"};

test("D2 download is a template prefilled with the selected aircraft identity", () => {
  assert.equal(aircraftD2CsvTemplate("359","900"), `${heading}\n359,900,,,,,,,,,,,,,\n`);
});

test("groups flat area rows and derives their hold", () => {
  const result = parseAircraftD2Csv(csv(row("LOWER,BLK,FWD,FLF,A1,1,900,4.77,10,9,11,-0.00031"),row("LOWER,BLK,FWD,FLF,A1,2,1000,6,12,11,13,0.0001")), decks, [], null, expected);
  assert.deepEqual(result.errors, []);
  assert.equal(result.rows.length, 1);
  assert.equal(result.rows[0].deckCode, "LOWER");
  assert.equal(result.rows[0].name, "FLF");
  assert.equal(result.rows[0].hasDoor, true);
  assert.equal(result.rows[0].maxWeight, 1900);
  assert.equal(result.rows[0].maxVolume, 10.77);
  assert.equal(result.rows[0].balanceFrom, 9);
  assert.equal(result.rows[0].balanceTo, 13);
  assert.deepEqual(result.rows[0].compartments[0].areas.map(area => [area.id, area.maxVolume]), [["1", 4.77], ["2", 6]]);
});

test("Deck ID routes a hold to a non-lower deck", () => {
  const result = parseAircraftD2Csv(csv(row("MAIN,BLK,FWD,,,,3400,,,,,-0.0002")), decks, [], null, expected);
  assert.deepEqual(result.errors, []);
  assert.equal(result.rows[0].deckCode, "MAIN");
});

test("VOL and all balance arm columns may be blank", () => {
  const result = parseAircraftD2Csv(csv(row("Lower Deck,BLK,FWD,,A1,1,900,,,,,-0.00031")), decks, [], null, expected);
  assert.deepEqual(result.errors, []);
  assert.equal(result.rows[0].maxVolume, null);
  assert.equal(result.rows[0].balanceCentroid, null);
  assert.equal(result.rows[0].compartments[0].areas[0].maxVolume, null);
});

test("a blank hold centroid is calculated from the saved C4 formula", () => {
  const formula = { referenceArm: 20, constantC: 1000 };
  const result = parseAircraftD2Csv(csv(row("LOWER,BLK,FWD,,A1,1,3400,,,,,-0.002")), decks, [], formula, expected);
  assert.deepEqual(result.errors, []);
  assert.equal(result.rows[0].balanceCentroid, 18);
});

test("rejects duplicate areas", () => {
  const duplicate = parseAircraftD2Csv(csv(row("LOWER,BLK,FWD,,A1,1,900,,,,,-0.00031"),row("LOWER,BLK,FWD,,A1,1,900,,,,,-0.00031")), decks, [], null, expected);
  assert.match(duplicate.errors.join(" "), /duplicated/i);
});

test("one D2 CSV imports ULD compartments and Bulk Areas",()=>{
  const result=parseAircraftD2Csv(csv(
    row("LOWER,ULD,FWD,FLF,1,,4626,,15.966,,,-0.00534"),
    row("LOWER,ULD,FWD,FLA,2,,9525,,19.682,,,-0.00349"),
    row("LOWER,ULD,AFT,ALA,4,,9525,,31.753,,,0.00254"),
    row("LOWER,BLK,ALB,,5,51,1841,11,36.142,,,0.00424"),
    row("LOWER,BLK,ALB,,5,52,667,4,36.372,,,0.00503"),
    row("LOWER,BLK,ALB,,5,53,272,2,36.527,,,0.00543")
  ),decks,[],null,expected);
  assert.deepEqual(result.errors,[]);
  assert.deepEqual(result.sections,["ULD","BULK"]);
  assert.deepEqual(result.source,expected);
  assert.deepEqual(result.rows.filter(item=>item.holdType==="ULD").map(item=>[item.name,item.compartments[0].id]),[["FLF","1"],["FLA","2"],["ALA","4"]]);
  const bulk=result.rows.find(item=>item.holdType==="BLK");
  assert.equal(bulk?.name,"ALB");
  assert.equal(bulk?.maxWeight,2780);
  assert.deepEqual(bulk?.compartments[0].areas.map(area=>area.id),["51","52","53"]);
});

test("blocks a CSV for a different aircraft before producing import rows",()=>{
  const result=parseAircraftD2Csv(csv(row("LOWER,BLK,ALB,,5,51,1841,11,36.142,,,0.00424","310","300")),decks,[],null,{typeCode:"359",subtype:"900"});
  assert.match(result.errors.join(" "),/CSV aircraft 310-300 does not match this page 359-900/);
  assert.equal(result.rows.length,0);
});

test("requires aircraft identity on every row",()=>{
  const result=parseAircraftD2Csv(csv(row("LOWER,BLK,ALB,,5,51,1841,11,36.142,,,0.00424","","")),decks,[],null,expected);
  assert.match(result.errors.join(" "),/Aircraft Type IATA and Series\/Sub-Type are required/);
  assert.equal(result.rows.length,0);
});

test("Door accepts Y or N consistently for each Hold",()=>{
  const noDoor=parseAircraftD2Csv(csv(row("LOWER,ULD,FWD,FLA,2,,9525,,19.682,,,-0.00349","310","300","N")),decks,[],null,expected);
  assert.deepEqual(noDoor.errors,[]);
  assert.equal(noDoor.rows[0].hasDoor,false);
  const conflict=parseAircraftD2Csv(csv(
    row("LOWER,BLK,ALB,,5,51,1841,11,36.142,,,0.00424","310","300","Y"),
    row("LOWER,BLK,ALB,,5,52,667,4,36.372,,,0.00503","310","300","N")
  ),decks,[],null,expected);
  assert.match(conflict.errors.join(" "),/same Door Y\/N value/);
});
