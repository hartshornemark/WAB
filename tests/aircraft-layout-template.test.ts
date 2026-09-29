import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {createHash} from "node:crypto";
import {parseLayoutVersion} from "../src/domain/aircraft-layout-template";
import {A319_LAYOUT,A320_LAYOUT} from "./fixtures/aircraft-layouts";
import {holdLayoutX} from "../src/domain/hold-layout";
import {carrierDrawingOrigin} from "../src/domain/carrier-drawing-origin";
import seeds from "../src/infrastructure/aircraft-layouts/seed.json";
const version=(i=0)=>({id:"fixture",aircraft_type:seeds[i].typeCode,aircraft_subtype:seeds[i].subtype,version:seeds[i].version,bucket:"aircraft-layouts",object_path:seeds[i].objectPath,sha256:seeds[i].sha256,byte_size:seeds[i].byteSize,nose_arm_m:seeds[i].noseArm,datum_description:seeds[i].datumDescription,datum_source:seeds[i].datumSource,source_drawing:seeds[i].sourceDrawing,calibration:seeds[i].calibration});
test("stored template contract preserves both approved calibrations and exact SVG bytes",()=>{
 for(const [i,approved] of [A319_LAYOUT,A320_LAYOUT].entries()){
  const parsed=parseLayoutVersion(version(i));
  const {asset,...expected}=approved;assert.ok(asset);
  assert.deepEqual(parsed.calibration,expected);
  const file=readFileSync(`src/assets/aircraft-layouts/${seeds[i].file}`);
  assert.equal(file.length,parsed.byte_size);
  assert.equal(createHash("sha256").update(file).digest("hex"),parsed.sha256);
 }
});
test("physical nose datum stays separate from the legacy A320 hold origin",()=>{
 const v=parseLayoutVersion(version(1));assert.equal(v.nose_arm_m,2.54);assert.equal(v.calibration.noseArm,0);
 const aircraft={...v.calibration,asset:"signed"};
 assert.equal(holdLayoutX(31.212+aircraft.holdArmOffsets!["5"],aircraft),holdLayoutX(31.212-2.735,A320_LAYOUT));
 assert.equal(holdLayoutX(9.012,{...aircraft,noseArm:v.nose_arm_m}),holdLayoutX(9.012,{...A320_LAYOUT,noseArm:2.54}));
});
test("missing, cross-aircraft and corrupt metadata cannot reach a renderer",()=>{
 assert.throws(()=>parseLayoutVersion(null),/published/);
 assert.throws(()=>parseLayoutVersion({...version(),object_path:"320/200/wrong.svg"}),/metadata/);
 assert.throws(()=>parseLayoutVersion({...version(),calibration:{...version().calibration,typeCode:"320"}}),/match/);
 assert.throws(()=>parseLayoutVersion({...version(),calibration:{...version().calibration,span:NaN}}),/span/);
 assert.throws(()=>parseLayoutVersion({...version(),calibration:{...version().calibration,holdArmDefaults:{"5":{from:30,to:20}}}}),/boundaries/);
 assert.throws(()=>parseLayoutVersion({...version(),calibration:{...version().calibration,asset:"https://untrusted.invalid/image.svg"}}),/match/);
});
test("additional aircraft can use the same contract without a code registry",()=>{
 const v=version();const object_path=`321/200/${v.sha256}.svg`;
 const parsed=parseLayoutVersion({...v,aircraft_type:"321",aircraft_subtype:"200",object_path,calibration:{...v.calibration,typeCode:"321",subtype:"200"}});
 assert.equal(parsed.calibration.typeCode,"321");
});
test("an assigned aircraft identity can reuse a verified family SVG",()=>{
 const source=version(seeds.findIndex(s=>s.typeCode==="321"&&s.subtype==="P2F"&&s.version===2));
 const parsed=parseLayoutVersion({...source,
  aircraft_type:"321",aircraft_subtype:"200",
  asset_aircraft_type:"321",asset_aircraft_subtype:"P2F",
  geometry_family_code:"AIRBUS_A321",geometry_profile_code:"STANDARD",
  calibration:{...source.calibration,typeCode:"321",subtype:"200"}
 });
 assert.equal(parsed.aircraft_subtype,"200");
 assert.equal(parsed.asset_aircraft_subtype,"P2F");
 assert.equal(parsed.geometry_profile_code,"STANDARD");
 assert.equal(parsed.object_path,source.object_path);
});
test("MAX 9 provisional inch calibration anchors nose and aft positions without metre mixing",()=>{
 const i=seeds.findIndex(s=>s.typeCode==="7M9");assert.ok(i>=0);
 const v=parseLayoutVersion(version(i));const c={...v.calibration,asset:"signed"};
 assert.equal(v.nose_arm_m,3.302);assert.equal(c.armUnit,"IN");
 assert.equal(holdLayoutX(130,c),244);
 assert.ok(Math.abs(holdLayoutX(130+c.length,c)-4)<1e-9);
 assert.ok(holdLayoutX(500,c)<holdLayoutX(400,c));
 const bytes=readFileSync(`src/assets/aircraft-layouts/${seeds[i].file}`);
 assert.equal(bytes.length,v.byte_size);assert.equal(createHash("sha256").update(bytes).digest("hex"),v.sha256);
});
test("737-800 D2 hold and D4 door arms share one station system",()=>{
 const i=seeds.findIndex(s=>s.typeCode==="738"&&s.subtype==="800");assert.ok(i>=0);
 const v=parseLayoutVersion(version(i));const c={...v.calibration,asset:"signed"};
 assert.equal(v.nose_arm_m,3.302);assert.equal(c.armUnit,"IN");
 assert.equal(c.length,1554);assert.equal(holdLayoutX(130,c),244);
 assert.ok(Math.abs(holdLayoutX(1684,c)-4)<1e-9);
 assert.equal(c.holdY+c.holdHeight/2,c.centreY);
 assert.equal(c.holdHeight,14);
 const ka=carrierDrawingOrigin("KA",c);
 assert.equal(ka.stationOriginX,c.tailX);
 assert.ok(Math.abs(holdLayoutX(0,ka)-c.tailX)<1e-9);
 assert.equal(ka.holdArmOffsets?.["1"],68.17);
 // The supplied SVG's forward cargo-door outline spans x 188.35229–195.81175.
 assert.ok(Math.abs(holdLayoutX(244+ka.holdArmOffsets!["1"],ka)-195.81175)<0.03);
 assert.ok(Math.abs(holdLayoutX(292+ka.holdArmOffsets!["1"],ka)-188.35229)<0.03);
 assert.ok(holdLayoutX(204,ka)>holdLayoutX(244,ka));
 assert.ok(Math.abs((holdLayoutX(204,ka)-holdLayoutX(244,ka))-40*240/1554)<1e-9);
 assert.ok(holdLayoutX(731,ka)>holdLayoutX(1009,ka));
 assert.ok(Math.abs((holdLayoutX(731,ka)-holdLayoutX(1009,ka))-278*240/1554)<1e-9);
 assert.equal(carrierDrawingOrigin("AB",c),c);
 const bytes=readFileSync(`src/assets/aircraft-layouts/${seeds[i].file}`);
 assert.equal(bytes.length,v.byte_size);assert.equal(createHash("sha256").update(bytes).digest("hex"),v.sha256);
});
test("permanent 737 publications use the common Boeing AMM datum authority",()=>{
 for(const [typeCode,versionNumber] of [["738",5],["7M9",2]] as const){
  const i=seeds.findIndex(s=>s.typeCode===typeCode&&s.version===versionNumber);assert.ok(i>=0);
  const v=parseLayoutVersion(version(i));
  assert.equal(v.nose_arm_m,3.302);assert.equal(v.calibration.noseArm,130);assert.equal(v.calibration.armUnit,"IN");
  assert.match(v.datum_source,/AMM Task 06-21-00/);assert.doesNotMatch(v.datum_description,/provisional/i);
  assert.doesNotMatch(v.calibration.diagramCaption??"",/provisional/i);
  const bytes=readFileSync(`src/assets/aircraft-layouts/${seeds[i].file}`);
  assert.equal(bytes.length,v.byte_size);assert.equal(createHash("sha256").update(bytes).digest("hex"),v.sha256);
 }
});
test("A350-900 v2 aligns its confirmed datum and overlays to the drawing centreline",()=>{
 const i=seeds.findIndex(s=>s.typeCode==="359"&&s.subtype==="900"&&s.version===2);assert.ok(i>=0);
 const v=parseLayoutVersion(version(i));const c={...v.calibration,asset:"signed"};
 assert.equal(v.nose_arm_m,1.84);assert.equal(c.noseArm,1.84);assert.equal(c.armUnit,"M");
 assert.ok(Math.abs(holdLayoutX(1.84,c)-246.2)<1e-9);
 assert.ok(Math.abs(holdLayoutX(68.64,c)-6.4)<1e-9);
 assert.equal(c.holdY+c.holdHeight/2,c.centreY);
});
test("A350-900 v3 keeps the datum and applies only the forward-hold drawing correction",()=>{
 const i=seeds.findIndex(s=>s.typeCode==="359"&&s.subtype==="900"&&s.version===3);assert.ok(i>=0);
 const v=parseLayoutVersion(version(i));const c={...v.calibration,asset:"signed"};
 assert.equal(v.nose_arm_m,1.84);assert.equal(c.noseArm,1.84);
 assert.deepEqual(c.holdArmOffsets,{FWD:6.75});
 const uncorrected=holdLayoutX(13.205,c),corrected=holdLayoutX(13.205+c.holdArmOffsets!.FWD,c);
 assert.ok(corrected<uncorrected);
 const bytes=readFileSync(`src/assets/aircraft-layouts/${seeds[i].file}`);
 assert.equal(bytes.length,v.byte_size);assert.equal(createHash("sha256").update(bytes).digest("hex"),v.sha256);
});
test("A350-900 v4 keeps the forward hold start ahead of the cargo-door opening",()=>{
 const i=seeds.findIndex(s=>s.typeCode==="359"&&s.subtype==="900"&&s.version===4);assert.ok(i>=0);
 const v=parseLayoutVersion(version(i));const c={...v.calibration,asset:"signed"};
 assert.deepEqual(c.holdArmOffsets,{FWD:3.4});
 assert.ok(Math.abs(holdLayoutX(13.205+c.holdArmOffsets!.FWD,c)-193.19)<0.03);
 const bytes=readFileSync(`src/assets/aircraft-layouts/${seeds[i].file}`);
 assert.equal(bytes.length,v.byte_size);assert.equal(createHash("sha256").update(bytes).digest("hex"),v.sha256);
});
test("A350-900 v5 aligns the Compartment 3 aft edge without moving the AFT hold",()=>{
 const i=seeds.findIndex(s=>s.typeCode==="359"&&s.subtype==="900"&&s.version===5);assert.ok(i>=0);
 const v=parseLayoutVersion(version(i));const c={...v.calibration,asset:"signed"};
 assert.deepEqual(c.holdArmOffsets,{FWD:3.4});
 assert.deepEqual(c.holdSubdivisionBreaks,{AFT:[51.71]});
 assert.ok(Math.abs(holdLayoutX(51.71,c)-67.2)<0.04);
 const bytes=readFileSync(`src/assets/aircraft-layouts/${seeds[i].file}`);
 assert.equal(bytes.length,v.byte_size);assert.equal(createHash("sha256").update(bytes).digest("hex"),v.sha256);
});
test("A350-900 v6 anchors the Compartment 3 aft edge to the saved D4 AFT-door start",()=>{
 const i=seeds.findIndex(s=>s.typeCode==="359"&&s.subtype==="900"&&s.version===6);assert.ok(i>=0);
 const v=parseLayoutVersion(version(i));const c={...v.calibration,asset:"signed"};
 assert.deepEqual(c.holdArmOffsets,{FWD:3.4});
 assert.deepEqual(c.holdSubdivisionBreaks,{AFT:[51.71]});
 assert.deepEqual(c.holdSubdivisionDoorStarts,{AFT:["AFT"]});
 const bytes=readFileSync(`src/assets/aircraft-layouts/${seeds[i].file}`);
 assert.equal(bytes.length,v.byte_size);assert.equal(createHash("sha256").update(bytes).digest("hex"),v.sha256);
});
test("A350-900 v7 tapers bulk Hold 5 toward the tail without changing its station limits",()=>{
 const i=seeds.findIndex(s=>s.typeCode==="359"&&s.subtype==="900"&&s.version===7);assert.ok(i>=0);
 const v=parseLayoutVersion(version(i));const profile=v.calibration.holdProfiles?.["5"];
 assert.ok(profile);assert.deepEqual(profile.points.map(point=>point.arm),[54.09,55,56.59]);
 assert.ok(profile.points.every((point,index,points)=>index===0||point.halfWidth<points[index-1].halfWidth));
 const bytes=readFileSync(`src/assets/aircraft-layouts/${seeds[i].file}`);
 assert.equal(bytes.length,v.byte_size);assert.equal(createHash("sha256").update(bytes).digest("hex"),v.sha256);
});
test("A321 P2F source outline preserves its CAD scale and shared deck centreline",()=>{
 const i=seeds.findIndex(s=>s.typeCode==="321"&&s.subtype==="P2F");assert.ok(i>=0);
 const v=parseLayoutVersion(version(i)),c={...v.calibration,asset:"signed"};
 assert.equal(c.length,44.62930078125);
 assert.equal(holdLayoutX(c.noseArm,c),244);
 assert.equal(holdLayoutX(c.noseArm+c.length,c),4);
 assert.equal(c.holdY+c.holdHeight/2,c.centreY);
 const bytes=readFileSync(`src/assets/aircraft-layouts/${seeds[i].file}`);
 assert.equal(bytes.length,v.byte_size);assert.equal(createHash("sha256").update(bytes).digest("hex"),v.sha256);
});
