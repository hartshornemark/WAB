import test from 'node:test';
import assert from 'node:assert/strict';
import { validateCommodities, CommodityInvalid, CommodityDenied, CommodityConflict } from '../src/domain/commodity-codes';
import { createCommodityCodes } from '../src/application/commodity-codes';
import { createCommodityAdapter } from '../src/infrastructure/supabase/commodity-adapter';
import { AuthenticationRequired, CarrierUnavailable, DataUnavailable } from '../src/domain/models';
import type { RequestClient } from '../src/infrastructure/supabase/server';
const rows = [{ code: 'B', description: 'Baggage' }];
const snapshot = { canView: true, canEdit: true, revision: 'old', rows, defaults: [] };
const auth = { currentUser: async () => ({ id: 'user', email: null }), signIn: async () => {}, signOut: async () => {} };
const carrier = { iata: 'ZZ', name: 'Airline', icao: 'ZZZ' };
const carriers = { listAuthorised: async () => [carrier], findAuthorised: async () => carrier };
test('commodity input normalises codes and strips identity fields', () => {
  assert.deepEqual(validateCommodities([{ code: ' b ', description: ' Baggage ', Carrier_IATA: 'XX' }]), rows);
});
test('commodity input rejects empty sets, duplicates, invalid lengths and malformed entries', () => {
  for (const value of [null, [], Array(201).fill(rows[0]), [{code:'b',description:'B'},rows[0]], [{code:'ABC',description:'B'}], [{code:'!',description:'B'}], [{code:'B',description:''}], [{code:'B',description:'x'.repeat(65)}], [{code:'B',description:'a\nb'}], [{}]]) assert.throws(() => validateCommodities(value), CommodityInvalid);
});
test('commodity application blocks expired sessions, inaccessible carriers and non-administrators', async () => {
  const repo = { get: async () => ({ ...snapshot, canEdit:false }), save: async (): Promise<never> => { assert.fail('write attempted'); } };
  await assert.rejects(createCommodityCodes({ ...auth, currentUser:async()=>null },carriers,repo).save('ZZ','old',rows), AuthenticationRequired);
  await assert.rejects(createCommodityCodes(auth,{ ...carriers,findAuthorised:async()=>null },repo).save('XX','old',rows), CarrierUnavailable);
  await assert.rejects(createCommodityCodes(auth,carriers,repo).save('ZZ','old',rows), CommodityDenied);
});
test('commodity application validates and preserves the original revision', async () => {
  let received: unknown;
  const app = createCommodityCodes(auth,carriers,{get:async()=>snapshot,save:async(...args)=>{received=args;return snapshot;}});
  await app.save('ZZ','original',[{code:' b ',description:' Baggage '}]);
  assert.deepEqual(received,['ZZ','original',rows]);
  await assert.rejects(app.save('ZZ','original',[]),CommodityInvalid);
});
test('commodity adapter translates database errors', async () => {
  for (const [code, kind] of [['42501',CommodityDenied],['40001',CommodityConflict],['22023',CommodityInvalid],['unknown',DataUnavailable]] as const) {
    const client = {schema:()=>({rpc:async()=>({error:{code},data:null})})} as unknown as RequestClient;
    await assert.rejects(createCommodityAdapter(client).save('ZZ','old',rows),kind);
  }
});
test('commodity adapter preserves unsaved defaults and rejects malformed responses', async () => {
  const client = (data:unknown)=>({schema:()=>({rpc:async()=>({data,error:null})})}) as unknown as RequestClient;
  const empty = {...snapshot, rows:[], defaults:rows};
  assert.deepEqual(await createCommodityAdapter(client(empty)).get('ZZ'),empty);
  await assert.rejects(createCommodityAdapter(client({...empty,defaults:[{}]})).get('ZZ'),DataUnavailable);
});
