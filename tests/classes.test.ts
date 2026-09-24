import test from 'node:test';
import assert from 'node:assert/strict';
import { validateClasses, ClassInvalid, ClassDenied, ClassConflict } from '../src/domain/class-codes';
import { createClassCodes } from '../src/application/class-codes';
import { createClassAdapter } from '../src/infrastructure/supabase/class-adapter';
import { AuthenticationRequired, CarrierUnavailable, DataUnavailable } from '../src/domain/models';
import type { RequestClient } from '../src/infrastructure/supabase/server';
const rows = [{ code:'Y',priority:4,description:'Economy' }];
const snapshot = {canView:true,canEdit:true,revision:'old',rows,defaults:[]};
const auth = {currentUser:async()=>({id:'user',email:null}),signIn:async()=>{},signOut:async()=>{}};
const carrier = {iata:'ZZ',name:'Airline',icao:'ZZZ'};
const carriers = {listAuthorised:async()=>[carrier],findAuthorised:async()=>carrier};
test('class codes accept only single ASCII letters and normalise lowercase',()=>{
 assert.deepEqual(validateClasses([{code:' y ',priority:4,description:' Economy ',Carrier_IATA:'XX'}]),rows);
 for(const code of ['1','!','YY','','é','ſ','ß','💺']) assert.throws(()=>validateClasses([{...rows[0],code}]),ClassInvalid);
});
test('one to four classes can use editable nonconsecutive priorities',()=>{
 for(let n=1;n<=4;n++) assert.equal(validateClasses(['F','C','W','Y'].slice(0,n).map((code,i)=>({code,priority:i+1,description:code}))).length,n);
 assert.deepEqual(validateClasses([rows[0],{code:'F',priority:1,description:'First'}]).map(r=>r.priority),[1,4]);
 for(const priority of [0,5,1.5,'1',null,NaN]) assert.throws(()=>validateClasses([{...rows[0],priority}]),ClassInvalid);
});
test('classes reject duplicate codes/priorities, empty sets and invalid descriptions',()=>{
 for(const value of [[],null,Array(5).fill(rows[0]),[rows[0],{code:'y',priority:1,description:'Duplicate'}],[rows[0],{code:'C',priority:4,description:'Duplicate'}],[{...rows[0],description:''}],[{...rows[0],description:'a\nb'}],[{...rows[0],description:'x'.repeat(65)}],[{}]]) assert.throws(()=>validateClasses(value),ClassInvalid);
 assert.equal(validateClasses([{...rows[0],description:'x'.repeat(64)}])[0].description.length,64);
});
test('class application denies missing sessions, inaccessible carriers and non-administrators',async()=>{
 const repo={get:async()=>({...snapshot,canEdit:false}),save:async():Promise<never>=>{assert.fail('write attempted');}};
 await assert.rejects(createClassCodes({...auth,currentUser:async()=>null},carriers,repo).save('ZZ','old',rows),AuthenticationRequired);
 await assert.rejects(createClassCodes(auth,{...carriers,findAuthorised:async()=>null},repo).save('XY','old',rows),CarrierUnavailable);
 await assert.rejects(createClassCodes(auth,carriers,repo).save('ZZ','old',rows),ClassDenied);
});
test('class application forwards validated editable values and original revision',async()=>{
 let received:unknown;
 const app=createClassCodes(auth,carriers,{get:async()=>snapshot,save:async(...args)=>{received=args;return snapshot;}});
 await app.save('ZZ','original',[{code:'c',priority:2,description:' Business '}]);
 assert.deepEqual(received,['ZZ','original',[{code:'C',priority:2,description:'Business'}]]);
 await assert.rejects(app.save('ZZ','original',[]),ClassInvalid);
});
test('class adapter translates permission, conflict, validation and prerequisite errors',async()=>{
 for(const [code,kind] of [['42501',ClassDenied],['40001',ClassConflict],['22023',ClassInvalid],['23514',ClassInvalid],['23503',ClassInvalid],['unknown',DataUnavailable]] as const){
 const client={schema:()=>({rpc:async()=>({error:{code},data:null})})} as unknown as RequestClient;
 await assert.rejects(createClassAdapter(client).save('ZZ','old',rows),kind);
 }
});
test('class adapter preserves existing classes and defaults and rejects malformed priority',async()=>{
 const client=(data:unknown)=>({schema:()=>({rpc:async()=>({data,error:null})})}) as unknown as RequestClient;
 assert.deepEqual(await createClassAdapter(client({...snapshot,extra:'hidden'})).get('ZZ'),snapshot);
 const empty={...snapshot,rows:[],defaults:rows};
 assert.deepEqual(await createClassAdapter(client(empty)).get('ZZ'),empty);
 await assert.rejects(createClassAdapter(client({...snapshot,rows:[{...rows[0],priority:'4'}]})).get('ZZ'),DataUnavailable);
});
