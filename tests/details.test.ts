import test from 'node:test';
import assert from 'node:assert/strict';
import { validateDetails, emptyDetails, DetailsInvalid, DetailsDenied, DetailsConflict } from '../src/domain/carrier-details';
import { createCarrierDetails } from '../src/application/carrier-details';
import { AuthenticationRequired, CarrierUnavailable, DataUnavailable } from '../src/domain/models';
import { createDetailsAdapter } from '../src/infrastructure/supabase/details-adapter';
import type { RequestClient } from '../src/infrastructure/supabase/server';
const valid = { ...emptyDetails, address1: 'Office', city: 'London', country: 'UK', weightUnit: 'KG', volumeUnit: 'm3', weightMethod: 'BASIC' };
const snapshot = { canView: true, canEdit: true, exists: true, revision: 'revision', values: valid };
const auth = { currentUser: async () => ({ id: 'user', email: null }), signIn: async () => {}, signOut: async () => {} };
const carrier = { iata: 'ZZ', name: 'Airline', icao: 'ZZZ' };
const carriers = { listAuthorised: async () => [carrier], findAuthorised: async () => carrier };
test('details validation trims values and strips unknown identity fields', () => {
  assert.deepEqual(validateDetails({ ...valid, city: ' London ', Carrier_IATA: 'XX' } as typeof valid), valid);
});
test('details validation rejects required, length, email, teletype and preference errors', () => {
  for (const changes of [{ city: '' }, { address1: 'x'.repeat(65) }, { email: 'bad' }, { teletype: 'SHORT' }, { weightUnit: 'g' }, { volumeUnit: '' }, { weightMethod: '' }, { indexDecimalPlaces: '3' }, { country: 'U\nK' }]) {
    assert.throws(() => validateDetails({ ...valid, ...changes }), DetailsInvalid);
  }
});
test('details save denies expired sessions before repository access', async () => {
  const denied = async (): Promise<never> => { assert.fail('repository called'); };
  const app = createCarrierDetails({ ...auth, currentUser: async () => null }, carriers, { get: denied, save: denied });
  await assert.rejects(app.save('ZZ', 'revision', valid), AuthenticationRequired);
});
test('details save checks carrier access and fresh edit permission', async () => {
  const repo = { get: async () => ({ ...snapshot, canEdit: false }), save: async (): Promise<never> => { assert.fail('mutation called'); } };
  await assert.rejects(createCarrierDetails(auth, carriers, repo).save('ZZ', 'revision', valid), DetailsDenied);
  await assert.rejects(createCarrierDetails(auth, { ...carriers, findAuthorised: async () => null }, repo).save('XX', 'revision', valid), CarrierUnavailable);
});
test('details service validates and forwards the original revision', async () => {
  let received: unknown;
  const app = createCarrierDetails(auth, carriers, { get: async () => snapshot, save: async (...args) => { received = args; return snapshot; } });
  await app.save('ZZ', 'original', { ...valid, city: ' London ' });
  assert.deepEqual(received, ['ZZ', 'original', valid, 'all']);
  await assert.rejects(app.save('ZZ', 'original', { ...valid, city: '' }), DetailsInvalid);
});
test('details adapter maps conflict and authorization failures without provider leakage', async () => {
  for (const [code, error] of [['40001', DetailsConflict], ['42501', DetailsDenied], ['OTHER', DataUnavailable]] as const) {
    const client = { schema: () => ({ rpc: async () => ({ data: null, error: { code } }) }) } as unknown as RequestClient;
    await assert.rejects(createDetailsAdapter(client).save('ZZ', 'revision', valid), error);
  }
});
test('details adapter rejects malformed response and limits returned fields', async () => {
  const client = (data: unknown) => ({ schema: () => ({ rpc: async () => ({ data, error: null }) }) }) as unknown as RequestClient;
  await assert.rejects(createDetailsAdapter(client({ ...snapshot, values: {} })).get('ZZ'), DataUnavailable);
  assert.deepEqual(await createDetailsAdapter(client({ ...snapshot, secret: 'not forwarded' })).get('ZZ'), snapshot);
});

test('A2 contacts can save before B1 units are chosen',()=>{
 const contactOnly={...valid,weightUnit:'',volumeUnit:'',weightMethod:''};
 assert.deepEqual(validateDetails(contactOnly,'contact'),contactOnly);
 assert.throws(()=>validateDetails(contactOnly),DetailsInvalid);
 assert.throws(()=>validateDetails({...contactOnly,city:''},'contact'),DetailsInvalid);
});

test('A2 save uses the contacts-only repository operation',async()=>{
 let operation='';
 const client={schema:()=>({rpc:async(name:string)=>{operation=name;return {data:snapshot,error:null};}})} as unknown as RequestClient;
 const app=createCarrierDetails(auth,carriers,createDetailsAdapter(client));
 await app.save('ZZ','revision',{...valid,weightUnit:'',volumeUnit:'',weightMethod:''},'contact');
 assert.equal(operation,'save_carrier_contacts');
});
