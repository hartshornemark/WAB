import test from "node:test";
import assert from "node:assert/strict";
import { createAuthAdapter } from "../src/infrastructure/supabase/auth-adapter";
import { createCarrierAdapter } from "../src/infrastructure/supabase/carrier-adapter";
import {createCarrierAdministrationAdapter}from"../src/infrastructure/supabase/carrier-administration-adapter";
import type { RequestClient } from "../src/infrastructure/supabase/server";
import { DataUnavailable, SignInFailed } from "../src/domain/models";
import {operationalLoadPlan} from "../src/infrastructure/supabase/operational-flight-adapter";
import type{LoadPlanningSolution}from"../src/domain/load-planning-solver";
const client = (value: unknown) => value as RequestClient;
test("auth adapter rejects anonymous identities and distinguishes outages", async () => {
  const authClient = (data: unknown, error: unknown = null) => client({ auth: { getUser: async () => ({ data, error }) }, schema: () => ({ rpc: async () => ({ data: null, error: null }) }) });
  assert.equal(await createAuthAdapter(authClient({ user: { id: "1", is_anonymous: true } })).currentUser(), null);
  assert.equal(await createAuthAdapter(authClient({}, { name: "AuthSessionMissingError" })).currentUser(), null);
  assert.equal(await createAuthAdapter(authClient({}, { status: 401 })).currentUser(), null);
  await assert.rejects(createAuthAdapter(authClient({}, { status: 503 })).currentUser(), DataUnavailable);
  assert.deepEqual(await createAuthAdapter(authClient({ user: { id: "1", email: "a@b.test" } })).currentUser(), { id: "1", email: "a@b.test", displayName: null });
});
test("sign in and sign out use auth adapter and never leak provider errors", async () => {
  const adapter = createAuthAdapter(client({ auth: {
    signInWithPassword: async () => ({ error: { message: "Sensitive provider details" } }),
    signOut: async (options: unknown) => { assert.deepEqual(options, { scope: "local" }); return { error: null }; },
  } }));
  await assert.rejects(adapter.signIn("a@b.test", "password"), SignInFailed);
  await adapter.signOut();
});
test("carrier adapter queries only the approved table and maps paginated results", async () => {
  const calls: unknown[] = [];
  const query = {
    select(columns: string) { assert.equal(columns, "Carrier_IATA,Carrier_Name,Carrier_ICAO"); return this; },
    order(column: string) { assert.equal(column, "Carrier_IATA"); return this; },
    async range(from: number, to: number) {
      calls.push([from, to]);
      return { data: from === 0 ? Array.from({ length: 100 }, (_, i) => ({ Carrier_IATA: String(i), Carrier_Name: `Carrier ${i}`, Carrier_ICAO: "ZZZ" })) : [{ Carrier_IATA: "ZZ", Carrier_Name: "Test Carrier", Carrier_ICAO: "ZZZ" }], error: null };
    },
    eq(column: string, value: string) { assert.equal(column, "Carrier_IATA"); assert.equal(value, "ZZ"); return this; },
    async maybeSingle() { return { data: null, error: null }; },
  };
  const adapter = createCarrierAdapter(client({ schema(name: string) {
    assert.equal(name, "Basic_Carrier_Record");
    return { from(table: string) { assert.equal(table, "MASTER_Carrier_Contact"); return query; } };
  } }));
  const carriers = await adapter.listAuthorised();
  assert.equal(carriers.length, 101);
  assert.deepEqual(carriers[100], { iata: "ZZ", name: "Test Carrier", icao: "ZZZ" });
  assert.deepEqual(calls, [[0, 99], [100, 199]]);
  assert.equal(await adapter.findAuthorised("ZZ"), null);
});
test("carrier administration adapter uses permission and creation RPCs",async()=>{
  const calls:unknown[]=[];const adapter=createCarrierAdministrationAdapter(client({schema:(name:string)=>{assert.equal(name,"Basic_Carrier_Record");return{rpc:async(fn:string,args:unknown)=>{calls.push([fn,args]);return fn==="can_create_carrier"?{data:true,error:null}:{data:{iata:"Z9",name:"Example Air",icao:"EXA"},error:null}}}}}));
  assert.equal(await adapter.canCreate(),true);
  assert.deepEqual(await adapter.create({iata:"Z9",name:"Example Air",icao:"EXA"}),{iata:"Z9",name:"Example Air",icao:"EXA"});
  assert.deepEqual(calls,[["can_create_carrier",{}],["create_carrier",{p_iata:"Z9",p_name:"Example Air",p_icao:"EXA"}]]);
});
test("carrier API errors fail closed rather than returning an empty list", async () => {
  const query = { select() { return this; }, order() { return this; }, range: async () => ({ data: null, error: { code: "PGRST106" } }) };
  await assert.rejects(createCarrierAdapter(client({ schema: () => ({ from: () => query }) })).listAuthorised(), DataUnavailable);
});

test("display name uses own-profile result and falls back safely on missing data", async () => {
  for (const [name, error, expected] of [[" Mark Hartshorne ", null, "Mark Hartshorne"], [null, null, null], ["", null, null], [null, { code: "unavailable" }, null]] as const) {
    const adapter = createAuthAdapter(client({ auth: { getUser: async () => ({ data: { user: { id: "1", email: "a@b.test" } }, error: null }) }, schema: (schema: string) => {
      assert.equal(schema, "Basic_Carrier_Record");
      return { rpc: async (fn: string, args: unknown) => { assert.equal(fn, "current_display_name"); assert.deepEqual(args, {}); return { data: name, error }; } };
    } }));
    assert.equal((await adapter.currentUser())?.displayName, expected);
  }
});

test("saved load-plan response retains the submitted solution",()=>{
  const solution:LoadPlanningSolution={status:"FEASIBLE",engine:"MANUAL",solveMilliseconds:0,assignments:[{loadId:"PAJ1",positionId:"A12"}],sequencePenalty:0,usedSimplicityGroups:0,trimDeviationScaled:0,messages:[]};
  const plan=operationalLoadPlan({edition:5,source:"MANUAL",assignments:solution.assignments,createdAt:"2026-10-08T12:00:00Z"},solution);
  assert.equal(plan.edition,5);
  assert.equal(plan.solution,solution);
  assert.deepEqual(plan.solution?.assignments,[{loadId:"PAJ1",positionId:"A12"}]);
});
