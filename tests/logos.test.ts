import test from "node:test";
import assert from "node:assert/strict";
import sharp from "sharp";
import { createCarrierLogos, MAX_LOGO_BYTES } from "../src/application/carrier-logos";
import { logoImageProcessor } from "../src/infrastructure/images/logo-image-processor";
import { AuthenticationRequired, LogoAccessDenied, LogoInputError } from "../src/domain/models";
import type { CarrierLogoRepository } from "../src/ports/carrier-logo-repository";
const auth = { currentUser: async () => ({ id: "operator", email: null }), signIn: async () => {}, signOut: async () => {} };
const carriers = { listAuthorised: async () => [{ iata: "ZZ", name: "Test", icao: "ZZZ" }], findAuthorised: async () => ({ iata: "ZZ", name: "Test", icao: "ZZZ" }) };
const images = { normalise: async (bytes: Uint8Array) => bytes };
function fixture(overrides: Partial<CarrierLogoRepository> = {}) {
  const calls: string[] = [];
  const logos: CarrierLogoRepository = {
    getMany: async () => ({}), canManage: async () => true,
    upload: async () => { calls.push("upload"); return "ZZ/new.png"; },
    setReference: async (_iata, path) => { calls.push(`reference:${path}`); return "ZZ/old.png"; },
    deleteFile: async path => { calls.push(`delete:${path}`); }, ...overrides,
  };
  return { logos, calls, app: createCarrierLogos(auth, carriers, logos, images) };
}
test("replacement publishes reference before deleting old file", async () => {
  const f = fixture(); await f.app.upload("ZZ", new Uint8Array([1]), "image/png");
  assert.deepEqual(f.calls, ["upload", "reference:ZZ/new.png", "delete:ZZ/old.png"]);
});
test("removal writes explicit no-logo reference", async () => {
  const f = fixture(); await f.app.remove("ZZ"); assert.deepEqual(f.calls, ["reference:null", "delete:ZZ/old.png"]);
});
test("ambiguous metadata failure never deletes the new object", async () => {
  const f = fixture({ setReference: async () => { throw new Error("network"); } });
  await assert.rejects(f.app.upload("ZZ", new Uint8Array([1]), "image/png")); assert.deepEqual(f.calls, ["upload"]);
});
test("cleanup failure is reported without undoing successful update", async () => {
  const f = fixture({ deleteFile: async () => { throw new Error("network"); } }); assert.deepEqual(await f.app.remove("ZZ"), { cleanupPending: true });
});
test("denied and signed-out users cannot mutate logos", async () => {
  const f = fixture({ canManage: async () => false });
  await assert.rejects(f.app.upload("ZZ", new Uint8Array([1]), "image/png"), LogoAccessDenied);
  await assert.rejects(f.app.remove("ZZ"), LogoAccessDenied);
  await assert.rejects(createCarrierLogos({ ...auth, currentUser: async () => null }, carriers, f.logos, images).remove("ZZ"), AuthenticationRequired);
  assert.deepEqual(f.calls, []);
});
test("invalid size and MIME are rejected before storage", async () => {
  const f = fixture();
  for (const [bytes, mime] of [[new Uint8Array(), "image/png"], [new Uint8Array(MAX_LOGO_BYTES + 1), "image/png"], [new Uint8Array([1]), "image/svg+xml"]] as const) await assert.rejects(f.app.upload("ZZ", bytes, mime), LogoInputError);
  assert.deepEqual(f.calls, []);
});
test("decoder rejects disguised SVG and corrupt image", async () => {
  await assert.rejects(logoImageProcessor.normalise(Buffer.from('<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"></svg>')), LogoInputError);
  await assert.rejects(logoImageProcessor.normalise(new Uint8Array([1, 2, 3])), LogoInputError);
});
test("normalisation preserves aspect ratio and alpha", async () => {
  const source = await sharp({ create: { width: 1800, height: 900, channels: 4, background: { r: 59, g: 102, b: 184, alpha: 0.5 } } }).png().toBuffer();
  const meta = await sharp(await logoImageProcessor.normalise(source)).metadata();
  assert.equal(meta.format, "png"); assert.equal(meta.width, 1024); assert.equal(meta.height, 512); assert.equal(meta.hasAlpha, true);
});
