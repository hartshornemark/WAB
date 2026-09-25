import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {createHash} from "node:crypto";
import {parseLayoutVersion} from "../src/domain/aircraft-layout-template";
import {A319_LAYOUT,A320_LAYOUT} from "./fixtures/aircraft-layouts";
import {holdLayoutX} from "../src/domain/hold-layout";
import seeds from "../src/infrastructure/aircraft-layouts/seed.json";
const version=(i=0)=>({id:"fixture",aircraft_type:seeds[i].typeCode,aircraft_subtype:seeds[i].subtype,version:1,bucket:"aircraft-layouts",object_path:seeds[i].objectPath,sha256:seeds[i].sha256,byte_size:seeds[i].byteSize,nose_arm_m:seeds[i].noseArm,datum_description:seeds[i].datumDescription,datum_source:seeds[i].datumSource,source_drawing:seeds[i].sourceDrawing,calibration:seeds[i].calibration});
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
