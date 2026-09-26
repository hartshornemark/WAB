import test from 'node:test';import assert from 'node:assert/strict';
import {seatRowIndexSuggestion as suggest} from '../src/domain/seat-row-index-suggestion';
const rows=(a:number|string|null,b:number|string|null,c:number|string|null=null)=>[{areaId:'A',rowNumber:1,index:a},{areaId:'A',rowNumber:2,index:b},{areaId:'A',rowNumber:3,index:c}];
test('suggests from two preceding physical rows and responds to corrections',()=>{
 assert.equal(suggest(rows('-.01000','-.00900'),2),-.008);
 assert.equal(suggest(rows('-.01000','-.00850'),2),-.007);
 assert.equal(suggest(rows(-.001,0),2),.001);
 assert.equal(suggest(rows(.001,0),2),-.001);
});
test('no suggestion across cabin boundaries, missing values, or entered target values',()=>{
 for(const blank of [null,'',' ','-','.','0.'])assert.equal(suggest(rows(blank,.1),2),null);
 for(const entered of [0,.2,'-'])assert.equal(suggest(rows(.1,.2,entered),2),null);
 const r=rows(.1,.2);r[2].areaId='B';assert.equal(suggest(r,2),null);
 assert.equal(suggest(rows(.1,.2),1),null);
});
test('uses physical order rather than numeric labels and rounds to five decimals',()=>{
 const r=rows(.00111,.00222);r[0].rowNumber=13;r[1].rowNumber=1;r[2].rowNumber=2;
 assert.equal(suggest(r,2),.00333);
 r[0].rowNumber=11;r[1].rowNumber=12;r[2].rowNumber=14;assert.equal(suggest(r,2),.00333);
});
