import test from 'node:test';
import assert from 'node:assert/strict';
import {adoptUld,customUld,validateUlds,uldEditRow,type UldSnapshot} from '../src/domain/uld-specifications';
const master=[{code:'AKE',type:'LD3',tare:'100',maximum:'1588',volume:'4.3',mainDeckOnly:false},{code:'AVE',type:'LD3',tare:'100',maximum:'1588',volume:'4.3',mainDeckOnly:false}];
const current:UldSnapshot={canView:true,canEdit:true,revision:'v1',weightUnit:'KG',volumeUnit:'m3',utilisesUlds:true,aircraftType:'319',aircraftSubtype:'100',rows:[],master};
test('ULD adoption uses master suggestions; first code of type becomes default',()=>{const a=adoptUld(master[0],current,[]);assert.equal(a.isDefault,true);assert.equal(a.tare,'100');const b=adoptUld(master[1],current,[a]);assert.equal(b.isDefault,false);assert.equal(validateUlds([a,b],current).length,2);});
test('ULD conversion uses carrier selected units',()=>{const row=adoptUld(master[0],{...current,weightUnit:'LB',volumeUnit:'ft3'},[]);assert.equal(row.tare,'220');assert.equal(row.maximum,'3501');assert.equal(row.volume,'151.85');});
test('ULD validates one default per type, unique code, and master membership',()=>{const a=adoptUld(master[0],current,[]);assert.throws(()=>validateUlds([{...a,isDefault:false}],current),/exactly one/);assert.throws(()=>validateUlds([a,a],current),/only once/);assert.throws(()=>validateUlds([{...a,code:'BAD'}],current),/master/);const b={...adoptUld(master[1],current,[a]),isDefault:true};assert.throws(()=>validateUlds([a,b],current),/exactly one/);});
test('ULD validates weights, volume, precision and remarks',()=>{const row=adoptUld(master[0],current,[]);for(const invalid of [{tare:'-1'},{maximum:'0'},{volume:'0'},{volume:'NaN'},{volume:'1.1234567'},{maximum:'99'},{remarks:'x'.repeat(2001)}])assert.throws(()=>validateUlds([{...row,...invalid}],current));assert.equal(validateUlds([{...row,tare:'90'}],current)[0].tare,'90');});
test('ULD permits removal of all adopted records',()=>{assert.deepEqual(validateUlds([],current),[]);});

test('ULD precision rules reject fractional weights and excess volume precision',()=>{const row=adoptUld(master[0],current,[]);for(const invalid of [{tare:'90.5'},{maximum:'1588.1'},{volume:'4.301'}])assert.throws(()=>validateUlds([{...row,...invalid}],current));assert.equal(validateUlds([{...row,volume:'4.31'}],current)[0].volume,'4.31');assert.deepEqual(uldEditRow({...row,tare:'90.000000',maximum:'1588.000000',volume:'4.300000'}),{...row,tare:'90',maximum:'1588',volume:'4.3'});});

test('Carrier-specific ULDs may use a new type or an existing type without master membership',()=>{
 const a=adoptUld(master[0],current,[]);const b={...customUld('xyz','NEW',[a]),tare:'100',maximum:'1000',volume:'4.25'};
 assert.equal(validateUlds([a,b],current)[1].type,'NEW');assert.equal(b.isCustom,true);assert.equal(b.isDefault,true);
 const c={...customUld('abc','LD3',[a]),tare:'100',maximum:'1000',volume:'4.25'};assert.equal(c.isDefault,false);assert.equal(validateUlds([a,c],current).length,2);
 assert.throws(()=>customUld('AKE','LD3',[a]),/already/);assert.throws(()=>customUld('A!','NEW',[]),/three/);
 assert.throws(()=>validateUlds([{...b,isCustom:false}],current),/master/);
});
test('ULD inventory pads serials and validates carrier codes and numeric ranges',()=>{const row=adoptUld(master[0],current,[]);const valid={...row,inventory:[{id:null,carrierCode:'ZZ',serialStart:'123',serialEnd:'199'}]};const inventory=validateUlds([valid],current)[0].inventory;assert.equal(inventory[0].serialStart,'00123');assert.equal(inventory[0].serialEnd,'00199');for(const range of [{carrierCode:'Z',serialStart:'1',serialEnd:'2'},{carrierCode:'ZZ',serialStart:'A1',serialEnd:'2'},{carrierCode:'ZZ',serialStart:'123456',serialEnd:'2'},{carrierCode:'ZZ',serialStart:'20',serialEnd:'10'}])assert.throws(()=>validateUlds([{...row,inventory:[{id:null,...range}]}],current));const short={id:null,carrierCode:'ZZ',serialStart:'1',serialEnd:'2'},padded={id:null,carrierCode:'ZZ',serialStart:'00001',serialEnd:'00002'};assert.throws(()=>validateUlds([{...row,inventory:[short,padded]}],current),/unique/);});

import {b5Completion} from '../src/domain/b5-status';
test('B5 is skipped per aircraft when ULD applicability is unchecked',()=>{assert.equal(b5Completion({...current,utilisesUlds:false}).page,'skipped');});
test('B5 requires at least one valid ULD Type when it applies',()=>{assert.equal(b5Completion(current).page,'incomplete');const row=adoptUld(master[0],current,[]);assert.equal(b5Completion({...current,rows:[row]}).page,'configured');});

test('accepts the six-character LD3-45 ULD Type',()=>{const row={...customUld('AKH','LD3-45',[]),tare:'100',maximum:'1500',volume:'4.25'};assert.equal(validateUlds([row],current)[0].type,'LD3-45');});
