import test from 'node:test';import assert from 'node:assert/strict';
import {calculatePantry,pantryDraft} from '@/domain/e2-pantry-allocations';
const galleys=[{id:'XFG',description:'Forward',maxWeight:857,centroid:200,index:-.01},{id:'XAG',description:'Aft',maxWeight:578,centroid:1000,index:.02}];
const row={pantryCode:'L',galleyLocations:'XFG/857 XAG/546',totalWeight:1403,balanceArm:0,index:0};
test('D6 allocations calculate total, weighted arm and additive index and round-trip',()=>{
 const calculated=calculatePantry(pantryDraft(row),galleys);
 assert.equal(calculated.totalWeight,1403);assert.equal(calculated.balanceArm,(857*200+546*1000)/1403);assert.ok(Math.abs(calculated.index!-2.35)<1e-10);
 assert.deepEqual(calculatePantry(pantryDraft(calculated),galleys),calculated);
});
test('single legacy galley uses saved total without guessing a split',()=>{assert.deepEqual(pantryDraft({...row,galleyLocations:'XFG',totalWeight:156}).allocations,[{locationId:'XFG',weight:156}]);assert.equal(pantryDraft({...row,galleyLocations:'XFG XAG'}).allocations[0].weight,null)});
test('invalid, duplicate, missing and overloaded galley entries fail',()=>{
 for(const allocations of [[{locationId:'BAD',weight:1}],[{locationId:'XFG',weight:null}],[{locationId:'XFG',weight:858}],[{locationId:'XFG',weight:1.5}],[{locationId:'XFG',weight:1},{locationId:'XFG',weight:2}]])assert.throws(()=>calculatePantry({...row,allocations},galleys));
});
