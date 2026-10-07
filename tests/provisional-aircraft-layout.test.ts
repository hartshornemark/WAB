import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { holdLayoutX } from "../src/domain/hold-layout";
import { provisionalAircraftLayout } from "../src/domain/provisional-aircraft-layout";

test("A310 review calibration is explicitly gated and never substitutes another aircraft",()=>{
  assert.equal(provisionalAircraftLayout("310","300",false),undefined);
  assert.equal(provisionalAircraftLayout("359","900",true),undefined);
  const layout=provisionalAircraftLayout("310","300",true)!;
  assert.equal(layout.noseArm,6.3825);
  assert.equal(layout.seatMapNoseArm,6.3825);
  assert.equal(layout.reviewDoorArmOffset,1.9675);
  assert.equal(layout.armUnit,"M");
  assert.equal(holdLayoutX(layout.noseArm,layout),244);
  assert.ok(Math.abs(holdLayoutX(layout.noseArm+layout.length,layout)-4)<1e-9);
  assert.equal(layout.holdY+layout.holdHeight/2,layout.centreY);
  assert.match(layout.diagramCaption??"",/Provisional/);
});

test("A310 review SVG bytes remain paired with the calibrated local asset URL",()=>{
  const layout=provisionalAircraftLayout("310","300",true)!;
  const bytes=readFileSync("public/aircraft-layouts/a310-300-provisional.svg");
  assert.equal(createHash("sha256").update(bytes).digest("hex"),"e4dfa29d0fd928f5517d96fd477e94680f38281eb4a0503aa7186cb3f9f9b64f");
  assert.match(layout.asset,/e4dfa29d0fd9/);
});
