import test from "node:test";
import assert from "node:assert/strict";
import { compactAssignedLoadFields, compactUldIdentityParts } from "../src/domain/compact-assigned-load";
import { a350HoldBoardFixture } from "./fixtures/a350-hold-board";

test("ULD type and full serial are separate tokens; arbitrary load references are preserved", () => {
  assert.deepEqual(compactUldIdentityParts("AKE0001ZZ", "AKE"), { type: "AKE", serial: "0001ZZ" });
  assert.deepEqual(compactUldIdentityParts("PKC12345ZZ", "PKC"), { type: "PKC", serial: "12345ZZ" });
  assert.deepEqual(compactUldIdentityParts("PAG1919ZZ", "PAG"), { type: "PAG", serial: "1919ZZ" });
  assert.equal(compactUldIdentityParts("LOAD-42", "AKE"), null);
  assert.equal(compactUldIdentityParts("AKE", "AKE"), null);
  assert.equal(compactUldIdentityParts("AKE0001ZZ", null), null);
});

test("compact assigned ULD shows identity, destination and kilograms without mutating placement data", () => {
  const load = { ...a350HoldBoardFixture().problem.loads[0], description: "PAG1919ZZ · unload HKG", weightKg: 3215 };
  const before = structuredClone(load);
  assert.deepEqual(compactAssignedLoadFields(load), { identity: "PAG1919ZZ", destination: "HKG", weight: "3,215 KG" });
  assert.equal(compactAssignedLoadFields(load, "LOAD-42").identity, "LOAD-42");
  assert.deepEqual(load, before);
});

test("bulk identity and weight remain visible even when a pieces count exists", () => {
  const load = { ...a350HoldBoardFixture().problem.loads[0], loadType: "BULK" as const, commodityCode: "BF", description: "BF · 2 PCS · unload HKG", weightKg: 30 };
  assert.deepEqual(compactAssignedLoadFields(load), { identity: "BF BULK", destination: "HKG", weight: "30 KG" });
});

test("planned baggage uses its reference rather than inventing a ULD number, and empty ULD retains weight", () => {
  const load = { ...a350HoldBoardFixture().problem.loads[0], id: "PLANNED_BAGGAGE:1", description: "BY BAGGAGE 1/2 · unload HKG", weightKg: 100 };
  assert.equal(compactAssignedLoadFields(load).identity, load.id);
  assert.equal(compactAssignedLoadFields(load, "BAG-001").identity, "BAG-001");
  assert.equal(compactAssignedLoadFields({ ...load, emptyUld: true, weightKg: 80 }).weight, "80 KG");
});
