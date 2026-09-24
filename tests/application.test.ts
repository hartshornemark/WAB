import test from "node:test";
import assert from "node:assert/strict";
import { createCarrierConfiguration } from "../src/application/carrier-configuration";
import { AuthenticationRequired, CarrierUnavailable, DataUnavailable, SignInFailed } from "../src/domain/models";
import type { AuthService } from "../src/ports/auth-service";
import type { CarrierRepository } from "../src/ports/carrier-repository";
import {createCarrierAdministration} from "../src/application/carrier-administration";
import {CarrierCreationDenied,CarrierIdentityInvalid} from "../src/domain/carrier-onboarding";
const user = { id: "user-1", email: "operator@example.test" };
const carrier = { iata: "ZZ", name: "Test Carrier", icao: "ZZZ" };
const auth: AuthService = { currentUser: async () => user, signIn: async () => {}, signOut: async () => {} };
const repository: CarrierRepository = { listAuthorised: async () => [carrier], findAuthorised: async iata => iata === "ZZ" ? carrier : null };
test("authenticated user can discover and select an authorised carrier", async () => {
  const app = createCarrierConfiguration(auth, repository);
  assert.deepEqual(await app.listCarriers(), { user, carriers: [carrier] });
  assert.deepEqual(await app.selectCarrier("ZZ"), { user, carrier });
});
test("missing session prevents both repository operations", async () => {
  const deny = async (): Promise<never> => { assert.fail("Repository must not run without authentication"); };
  const app = createCarrierConfiguration({ ...auth, currentUser: async () => null }, { listAuthorised: deny, findAuthorised: deny });
  await assert.rejects(app.listCarriers(), AuthenticationRequired);
  await assert.rejects(app.selectCarrier("ZZ"), AuthenticationRequired);
});
test("a changed URL does not authorise another carrier", async () => {
  await assert.rejects(createCarrierConfiguration(auth, repository).selectCarrier("XX"), CarrierUnavailable);
});
test("revoked carrier access is checked again after discovery", async () => {
  const app = createCarrierConfiguration(auth, { ...repository, findAuthorised: async () => null });
  assert.equal((await app.listCarriers()).carriers.length, 1);
  await assert.rejects(app.selectCarrier("ZZ"), CarrierUnavailable);
});
test("empty authorised list is valid, while a service failure remains an error", async () => {
  assert.deepEqual((await createCarrierConfiguration(auth, { ...repository, listAuthorised: async () => [] }).listCarriers()).carriers, []);
  await assert.rejects(createCarrierConfiguration(auth, { ...repository, listAuthorised: async () => { throw new DataUnavailable(); } }).listCarriers(), DataUnavailable);
});
test("solution administrator carrier creation normalises and validates master identity",async()=>{
  let received:unknown;
  const admin=createCarrierAdministration(auth,{canCreate:async()=>true,create:async input=>{received=input;return input}});
  assert.deepEqual(await admin.create({iata:" z9 ",name:" Example Air ",icao:" exa "}),{iata:"Z9",name:"Example Air",icao:"EXA"});
  assert.deepEqual(received,{iata:"Z9",name:"Example Air",icao:"EXA"});
  await assert.rejects(admin.create({iata:"Z",name:"Example Air",icao:"EXA"}),CarrierIdentityInvalid);
});
test("carrier creation requires both a session and the global creation permission",async()=>{
  let created=false;const repo={canCreate:async()=>false,create:async(input:typeof carrier)=>{created=true;return input}};
  await assert.rejects(createCarrierAdministration(auth,repo).create(carrier),CarrierCreationDenied);
  await assert.rejects(createCarrierAdministration({...auth,currentUser:async()=>null},repo).access(),AuthenticationRequired);
  assert.equal(created,false);
});
test("invalid credentials input is rejected before authentication; password is preserved", async () => {
  let received: string[] = [];
  const app = createCarrierConfiguration({ ...auth, signIn: async (...args) => { received = args; } }, repository);
  await assert.rejects(app.signIn("invalid", "password"), SignInFailed);
  assert.equal(received.length, 0);
  await app.signIn("  operator@example.test  ", " password ");
  assert.deepEqual(received, ["operator@example.test", " password "]);
});
