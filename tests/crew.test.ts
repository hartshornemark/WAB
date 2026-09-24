import test from 'node:test';
import assert from 'node:assert/strict';
import { validateCrewWeights, crewDraft, selectHoldCategory, CrewInvalid, CrewDenied, CrewConflict, type CrewValues } from '../src/domain/crew-weights';
import { createCrewWeights } from '../src/application/crew-weights';
import { createCrewAdapter } from '../src/infrastructure/supabase/crew-adapter';
import { AuthenticationRequired, CarrierUnavailable, DataUnavailable } from '../src/domain/models';
import type { RequestClient } from '../src/infrastructure/supabase/server';
const values:CrewValues={includesHandBaggage:true,allFlights:false,longhaul:true,shorthaul:true,flightDeckMale:85,flightDeckFemale:85,cabinMale:75,cabinFemale:75,flightDeckHand:null,cabinHand:null,flightDeckLong:0,flightDeckShort:0,flightDeckOther:null,cabinLong:0,cabinShort:0,cabinOther:null};
const snapshot={canView:true,canEdit:true,exists:true,revision:'old',unit:'KG' as const,values};
const auth={currentUser:async()=>({id:'user',email:null}),signIn:async()=>{},signOut:async()=>{}};
const carrier={iata:'ZZ',name:'Airline',icao:'ZZZ'};
const carriers={listAuthorised:async()=>[carrier],findAuthorised:async()=>carrier};
test('crew draft preserves zero versus unspecified and validates numeric fields',()=>{
 const draft=crewDraft(values);assert.equal(draft.flightDeckLong,'0');assert.equal(draft.flightDeckOther,'');
 assert.deepEqual(validateCrewWeights({...draft,Carrier_IATA:'XX'}),values);
});
test('separate hand baggage is required only when not included',()=>{
 assert.deepEqual(validateCrewWeights(values),values);
 assert.throws(()=>validateCrewWeights({...values,includesHandBaggage:false}),CrewInvalid);
 assert.throws(()=>validateCrewWeights({...values,includesHandBaggage:false,flightDeckHand:5}),CrewInvalid);
 assert.equal(validateCrewWeights({...values,includesHandBaggage:false,flightDeckHand:5,cabinHand:0}).cabinHand,0);
 assert.equal(validateCrewWeights({...values,includesHandBaggage:true,flightDeckHand:5,cabinHand:6}).flightDeckHand,5);
});
test('crew validation rejects missing, fractional, negative, boolean and excessive numbers',()=>{
 for(const changes of [{flightDeckMale:0},{flightDeckMale:null},{cabinMale:''},{cabinMale:75.5},{flightDeckLong:-1},{flightDeckLong:'1e3'},{flightDeckOther:true},{flightDeckHand:2147483648},{includesHandBaggage:'false'},{cabinFemale:undefined}]) assert.throws(()=>validateCrewWeights({...values,...changes}),CrewInvalid);
});
test('crew application enforces session, carrier and administrator access',async()=>{
 const repo={get:async()=>({...snapshot,canEdit:false}),save:async():Promise<never>=>{assert.fail('write attempted');}};
 await assert.rejects(createCrewWeights({...auth,currentUser:async()=>null},carriers,repo).save('ZZ','old',values),AuthenticationRequired);
 await assert.rejects(createCrewWeights(auth,{...carriers,findAuthorised:async()=>null},repo).save('XY','old',values),CarrierUnavailable);
 await assert.rejects(createCrewWeights(auth,carriers,repo).save('ZZ','old',values),CrewDenied);
});
test('crew application requires a unit and preserves revision for atomic conflict detection',async()=>{
 let received:unknown;const repo={get:async()=>snapshot,save:async(...args:unknown[])=>{received=args;return snapshot;}};
 await createCrewWeights(auth,carriers,repo).save('ZZ','original',crewDraft(values));assert.deepEqual(received,['ZZ','original',values]);
 await assert.rejects(createCrewWeights(auth,carriers,{...repo,get:async()=>({...snapshot,unit:null})}).save('ZZ','old',values),CrewInvalid);
});
test('crew adapter translates database errors without leaking provider details',async()=>{
 for(const [code,kind] of [['42501',CrewDenied],['40001',CrewConflict],['22023',CrewInvalid],['23514',CrewInvalid],['23503',CrewInvalid],['unknown',DataUnavailable]] as const){
 const client={schema:()=>({rpc:async()=>({error:{code},data:null})})} as unknown as RequestClient;
 await assert.rejects(createCrewAdapter(client).save('ZZ','old',values),kind);
 }
});
test('crew adapter rejects malformed responses and preserves nulls and included flag',async()=>{
 const client=(data:unknown)=>({schema:()=>({rpc:async()=>({data,error:null})})}) as unknown as RequestClient;
 assert.deepEqual(await createCrewAdapter(client({...snapshot,extra:'hidden'})).get('ZZ'),snapshot);
 for(const invalid of [{...snapshot,unit:'g'},{...snapshot,values:{...values,flightDeckHand:'5'}},{...snapshot,values:{...values,cabinFemale:undefined}}]) await assert.rejects(createCrewAdapter(client(invalid)).get('ZZ'),DataUnavailable);
});

test('hold categories are exclusive and preserve deselected weight values',()=>{
 const selected=selectHoldCategory({...values,flightDeckOther:12,cabinOther:10},'allFlights',true);
 assert.equal(selected.longhaul,false);assert.equal(selected.shorthaul,false);assert.equal(selected.flightDeckLong,0);
 const specific=selectHoldCategory(selected,'longhaul',true);assert.equal(specific.allFlights,false);assert.equal(specific.flightDeckOther,12);
 const both=selectHoldCategory(specific,'shorthaul',true);assert.equal(both.longhaul,true);assert.equal(both.shorthaul,true);
 assert.equal(validateCrewWeights(selected).cabinOther,10);
});
test('selected hold categories require both weights and a valid exclusive selection',()=>{
 for(const change of [{allFlights:false,longhaul:false,shorthaul:false},{allFlights:true},{longhaul:'true'},{flightDeckLong:null},{cabinShort:''}]) assert.throws(()=>validateCrewWeights({...values,...change}),CrewInvalid);
 assert.equal(validateCrewWeights({...values,longhaul:false,shorthaul:false,allFlights:true,flightDeckOther:0,cabinOther:0}).flightDeckOther,0);
});
