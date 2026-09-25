import test from 'node:test';
import assert from 'node:assert/strict';
import {fuelRowGeneration, mergeFuelRows} from '../src/domain/fuel-row-generation';
import {validateAircraftC8Section} from '../src/domain/aircraft-c8';
const range={start:'0',last:'1000',increment:'250',includeLast:false};
test('fuel generation includes zero and skips existing weights',()=>{
 const p=fuelRowGeneration(range,[250,750]);assert.deepEqual(p.weights,[0,500,1000]);assert.equal(p.skipped,2);
});
test('off-increment last weight is included only on request',()=>{
 assert.deepEqual(fuelRowGeneration({...range,last:'900'},[]).weights,[0,250,500,750]);
 assert.deepEqual(fuelRowGeneration({...range,last:'900',includeLast:true},[]).weights,[0,250,500,750,900]);
});
test('generation rejects invalid and excessive ranges before allocating',()=>{
 for(const patch of [{start:''},{start:'-1'},{start:'1.5'},{increment:'0'},{last:'-3'},{last:'1000000000',increment:'1'},{start:'1001'}])assert.throws(()=>fuelRowGeneration({...range,...patch},[]));
});
test('merge preserves entered values and blank rows, sorts, and is repeatable',()=>{
 const existing={fuelWeight:500,indexValue:1.234,draftId:3};const blank={fuelWeight:NaN,indexValue:NaN,draftId:4};let id=4;
 const create=(fuelWeight:number)=>({fuelWeight,indexValue:NaN,draftId:++id});
 const rows=mergeFuelRows([existing,blank],[0,500,1000],create);
 assert.equal(rows[1],existing);assert.equal(rows[3],blank);assert.deepEqual(rows.slice(0,3).map(r=>r.fuelWeight),[0,500,1000]);
 assert.equal(mergeFuelRows(rows,[0,500,1000],create).length,4);assert.ok(Number.isNaN(rows[0].indexValue));
});
test('zero fuel weight saves but missing Index cannot save',()=>{
 const row={specificGravity:.8,fuelWeight:0,fuelVolume:null,hArm:null,indexValue:0};
 assert.doesNotThrow(()=>validateAircraftC8Section({enabled:true,rows:[row]},'standard'));
 assert.throws(()=>validateAircraftC8Section({enabled:true,rows:[{...row,indexValue:NaN}]},'standard'));
});
test('save supplies one zero origin per SG and preserves existing origins',()=>{
 const row={specificGravity:.8,fuelWeight:500,fuelVolume:null,hArm:null,indexValue:1.2};
 const result=validateAircraftC8Section({enabled:true,rows:[row,{...row,specificGravity:.81},{...row,fuelWeight:0,indexValue:.1}]},'standard');
 assert.ok('enabled' in result);
 const rows=result.rows as typeof row[];
 assert.equal(rows.length,4);assert.equal(rows.find(r=>r.specificGravity===.8&&r.fuelWeight===0)?.indexValue,.1);
 assert.equal(rows.find(r=>r.specificGravity===.81&&r.fuelWeight===0)?.indexValue,0);
});
