import test from 'node:test';
import assert from 'node:assert/strict';
import seeds from '../src/infrastructure/aircraft-layouts/seed.json';
import {holdLayoutX,type AircraftLayoutCalibration} from '../src/domain/hold-layout';
const layout={...seeds.find(s=>s.typeCode==='DH3')!.calibration,asset:'test.svg'} as AircraftLayoutCalibration;
test('DH3 station anchors align with the source drawing independently of nose datum',()=>{
 assert.equal(layout.noseArm,43);
 assert.ok(Math.abs(holdLayoutX(43,layout)-212.0727257196549)<1e-9);
 assert.ok(Math.abs(holdLayoutX(109,layout)-192.2)<1e-9);
 assert.ok(Math.abs(holdLayoutX(577.28,layout)-51.2)<1e-9);
 assert.equal(holdLayoutX(662,layout),holdLayoutX(662,{...layout,noseArm:100}));
});
test('DH3 hold profile retains the approved bounds and indicative join',()=>{
 const p=layout.combinedHoldProfile!;
 assert.deepEqual(p.points.map(p=>p.arm),[626.43,662,714.5]);
 assert.equal(p.joinArm,662);
 assert.ok(holdLayoutX(714.5,layout)>layout.cropLeft);
 assert.ok(p.points[2].halfWidth<p.points[1].halfWidth);
});
