import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { PGlite } from "@electric-sql/pglite";
import ruleCases from "./fixtures/cargo-capacity/rule-unit-cases-v2.json";
import { validateCargoCapacityProblem, validateCargoCapacityResult, type CargoCapacityProblem, type CargoCapacityResult } from "../src/domain/cargo-capacity";

async function install(db: PGlite) {
  await db.exec(readFileSync("solver/reference/max_net_cargo_v2.sql", "utf8"));
  await db.exec(readFileSync("solver/reference/frontier_net_cargo_v2.sql", "utf8"));
}
async function run(db: PGlite, fn: "max_net_cargo_v2" | "exhaustive_net_cargo_v2", p: CargoCapacityProblem) {
  const r = (await db.query<{ result: CargoCapacityResult }>(`select capacity_reference.${fn}($1::jsonb) result`, [JSON.stringify(p)])).rows[0].result;
  validateCargoCapacityResult(p, { ...r, engine: "OR-TOOLS CP-SAT", solveMilliseconds: 0 });
  return r;
}

// Synthetic tiny layouts only. No import/read of the seven frozen scenario files.
function smallProblem(seed: number, tiny = false): CargoCapacityProblem {
  let state = seed + 1;
  const draw = (n: number) => { state = (Math.imul(state, 1664525) + 1013904223) >>> 0; return state % n; };
  const p: CargoCapacityProblem = {
    mode: "CARGO_CAPACITY", aircraftType: "359", rulesVersion: "A350_MAX_NET_CARGO_V2", inputRevision: `synthetic-frontier-${seed}-${tiny}`, timeLimitSeconds: 2,
    maximumZeroFuelWeightGrams: 5 + draw(tiny ? 10 : 45), dryOperatingWeightGrams: 1, passengerWeightGrams: draw(4), cargoDensityGramsPerM3: [333333, 1000000, 2000000][draw(3)],
    groups: [
      { id: "H", parentId: null, maximumGrossWeightGrams: 5 + draw(35), maximumBulkVolumeMillilitres: seed % 3 ? null : draw(12) },
      { id: "A", parentId: "H", maximumGrossWeightGrams: 3 + draw(22), maximumBulkVolumeMillilitres: seed % 2 ? draw(10) : null },
      { id: "B", parentId: "H", maximumGrossWeightGrams: 3 + draw(22), maximumBulkVolumeMillilitres: null },
    ], positions: [], bulkAreas: [], baggageUlds: [], fixedLoads: [],
  };
  for (let i = 0; i < (tiny ? 3 : 4); i++) {
    const group = i % 2 ? "B" : "A", tare = draw(3);
    p.positions.push({ id: `P${i}`, kind: i === 0 && seed % 2 ? "PALLET" : "CONTAINER", groupId: group,
      occupiedBayIds: [`${group}:${seed % 4 === 0 ? 0 : i}`], tareWeightGrams: tare, maximumGrossWeightGrams: tare + 1 + draw(tiny ? 3 : 10), maximumVolumeMillilitres: 1 + draw(8) });
  }
  for (let i = 0; i < (tiny ? 1 : 2); i++) p.bulkAreas.push({ id: `AREA${i}`, groupId: i ? "B" : "A", maximumGrossWeightGrams: 1 + draw(tiny ? 3 : 10), maximumVolumeMillilitres: 1 + draw(8) });
  for (let i = 0; i < seed % (tiny ? 2 : 3); i++) p.baggageUlds.push({ id: `BAG${i}`, netWeightGrams: 1 + draw(5), volumeMillilitres: 1 + draw(9), compatiblePositionIds: p.positions.filter(r => r.kind === "CONTAINER" && draw(4) !== 0).map(r => r.id) });
  if (seed % 4 === 1) p.fixedLoads.push({ id: "FIXED-BULK", kind: "BAGGAGE_BULK", grossWeightGrams: draw(5), bulkVolumeMillilitres: draw(7), bulkAreaId: "AREA0", groupId: null, occupiedBayIds: [] });
  if (seed % 5 === 0) p.fixedLoads.push({ id: "FIXED-ULD", kind: "OTHER", grossWeightGrams: draw(4), bulkVolumeMillilitres: 0, bulkAreaId: null, groupId: "B", occupiedBayIds: seed % 10 ? [] : ["B:1"] });
  return validateCargoCapacityProblem(p);
}

// A third oracle enumerates integer cargo weights directly, rather than sharing
// the SQL max-flow evaluator or frontier summaries. Small gram limits only.
function integerWeightOracle(p: CargoCapacityProblem): number | null {
  let best: number | null = null;
  const cargo: { positionId: string; netWeightGrams: number }[] = [];
  const bags: { loadId: string; positionId: string }[] = [];
  const bulk: { areaId: string; netWeightGrams: number }[] = [];
  function finish() {
    if (bags.length !== p.baggageUlds.length) return;
    const net = [...cargo, ...bulk].reduce((sum, r) => sum + r.netWeightGrams, 0);
    const tare = cargo.reduce((sum, r) => sum + p.positions.find(pos => pos.id === r.positionId)!.tareWeightGrams, 0);
    try {
      validateCargoCapacityResult(p, { mode: p.mode, aircraftType: p.aircraftType, rulesVersion: p.rulesVersion, inputRevision: p.inputRevision, engine: "OR-TOOLS CP-SAT", solveMilliseconds: 0, status: "OPTIMAL",
        arrangement: { cargoUlds: cargo, baggageUlds: bags, bulkCargo: bulk, cargoNetWeightGrams: net, cargoTareWeightGrams: tare, cargoGrossWeightGrams: net + tare } });
      best = best === null ? net : Math.max(best, net);
    } catch { /* This enumerated assignment is physically infeasible. */ }
  }
  function areas(i: number) {
    if (i === p.bulkAreas.length) return finish();
    areas(i + 1);
    for (let w = 1; w <= p.bulkAreas[i].maximumGrossWeightGrams; w++) { bulk.push({ areaId: p.bulkAreas[i].id, netWeightGrams: w }); areas(i + 1); bulk.pop(); }
  }
  function positions(i: number) {
    if (i === p.positions.length) return areas(0);
    positions(i + 1);
    const pos = p.positions[i];
    for (let w = 1; w <= pos.maximumGrossWeightGrams - pos.tareWeightGrams; w++) { cargo.push({ positionId: pos.id, netWeightGrams: w }); positions(i + 1); cargo.pop(); }
    for (const bag of p.baggageUlds) if (bag.compatiblePositionIds.includes(pos.id) && !bags.some(b => b.loadId === bag.id)) { bags.push({ loadId: bag.id, positionId: pos.id }); positions(i + 1); bags.pop(); }
  }
  positions(0);
  return best;
}

test("exact group frontier agrees with exhaustive arrangement search on known and generated small cases", async t => {
  const db = new PGlite();
  try {
    await install(db);
    const inputs = [...ruleCases.cases.map(c => validateCargoCapacityProblem(c.input)), ...Array.from({ length: 72 }, (_, i) => smallProblem(i))];
    for (const p of inputs) await t.test(p.inputRevision + "-" + inputs.indexOf(p), async () => {
      const old = await run(db, "exhaustive_net_cargo_v2", p), replacement = await run(db, "max_net_cargo_v2", p);
      assert.equal(replacement.status, old.status);
      assert.equal(replacement.arrangement?.cargoNetWeightGrams ?? null, old.arrangement?.cargoNetWeightGrams ?? null);
    });
  } finally { await db.close(); }
});

test("frontier also agrees with independent exhaustive integer-weight enumeration", async () => {
  const db = new PGlite();
  try {
    await install(db);
    for (let seed = 0; seed < 20; seed++) {
      const p = smallProblem(seed, true), r = await run(db, "max_net_cargo_v2", p);
      assert.equal(r.arrangement?.cargoNetWeightGrams ?? null, integerWeightOracle(p), `seed ${seed}`);
    }
  } finally { await db.close(); }
});

test("obvious impossibilities, exact pruning and resource failure are explicit", async () => {
  const db = new PGlite();
  try {
    await install(db);
    const p = structuredClone(ruleCases.cases[0].input) as CargoCapacityProblem;
    p.baggageUlds = Array.from({ length: 3 }, (_, i) => ({ id: `B${i}`, netWeightGrams: 1, volumeMillilitres: 1, compatiblePositionIds: ["C1", "C2"] }));
    const r = (await db.query<{ result: { status: string; diagnostics: { earlyRejection: string } } }>("select capacity_reference.frontier_net_cargo_v2($1::jsonb,1) result", [JSON.stringify(p)])).rows[0].result;
    assert.equal(r.status, "INFEASIBLE"); assert.equal(r.diagnostics.earlyRejection, "BAGGAGE_POSITION_COUNT");
    await assert.rejects(db.query("select capacity_reference.frontier_net_cargo_v2($1::jsonb,1)", [JSON.stringify(ruleCases.cases[0].input)]), /state limit; no optimum established/);
    const bad = structuredClone(ruleCases.cases[0].input) as CargoCapacityProblem;
    bad.groups.push({ id: "OTHER", parentId: null, maximumGrossWeightGrams: 10000, maximumBulkVolumeMillilitres: null }); bad.positions[0].groupId = "OTHER";
    await assert.rejects(db.query("select capacity_reference.max_net_cargo_v2($1::jsonb)", [JSON.stringify(bad)]), /Physical bay claimed across different groups/);
    const states = [
      { mask: ["A"], live: [], base: 3, u: 7, b: 2, t: 8, bags: { A: "P" }, cargo: ["C"] },
      { mask: ["A"], live: [], base: 4, u: 6, b: 2, t: 7, bags: { A: "Q" }, cargo: ["D"] },
      { mask: ["A"], live: [], base: 3, u: 6, b: 4, t: 8, bags: { A: "R" }, cargo: ["E"] },
      { mask: ["B"], live: [], base: 3, u: 7, b: 2, t: 8, bags: { B: "P" }, cargo: ["C"] },
    ];
    const kept = (await db.query<{ result: unknown[] }>("select capacity_reference.prune_states($1::jsonb,100) result", [JSON.stringify(states)])).rows[0].result;
    assert.equal(kept.length, 3); // Preserve the ULD/Bulk trade-off and different baggage identity.
  } finally { await db.close(); }
});

test("several compartments combine under a shared hold and aircraft cap without whole-aircraft enumeration", async () => {
  const db = new PGlite();
  try {
    await install(db);
    const p: CargoCapacityProblem = { mode: "CARGO_CAPACITY", aircraftType: "359", rulesVersion: "A350_MAX_NET_CARGO_V2", inputRevision: "synthetic-four-compartments", timeLimitSeconds: 2,
      maximumZeroFuelWeightGrams: 52, dryOperatingWeightGrams: 1, passengerWeightGrams: 1, cargoDensityGramsPerM3: 1000000,
      groups: [{ id: "H", parentId: null, maximumGrossWeightGrams: 50, maximumBulkVolumeMillilitres: null }], positions: [], bulkAreas: [], baggageUlds: [], fixedLoads: [] };
    for (let c = 0; c < 4; c++) {
      p.groups.push({ id: `C${c}`, parentId: "H", maximumGrossWeightGrams: 18, maximumBulkVolumeMillilitres: null });
      for (let i = 0; i < 3; i++) p.positions.push({ id: `C${c}P${i}`, kind: "CONTAINER", groupId: `C${c}`, occupiedBayIds: [`C${c}:${i}`], tareWeightGrams: 1, maximumGrossWeightGrams: 6, maximumVolumeMillilitres: 10 });
    }
    for (let i = 0; i < 3; i++) p.baggageUlds.push({ id: `B${i}`, netWeightGrams: i + 1, volumeMillilitres: 1, compatiblePositionIds: p.positions.map(r => r.id) });
    validateCargoCapacityProblem(p);
    const r = await run(db, "max_net_cargo_v2", p);
    // Baggage gross is 9. Net 35 needs at least seven cargo tares: 35+7+9>50.
    // Net 34 fits with seven cargo ULDs, so 34 is an independent upper bound attained.
    assert.equal(r.arrangement?.cargoNetWeightGrams, 34);
    const reordered = structuredClone(p);
    reordered.positions.reverse(); reordered.groups.reverse(); reordered.baggageUlds.reverse();
    assert.equal((await run(db, "max_net_cargo_v2", reordered)).arrangement?.cargoNetWeightGrams, 34);
  } finally { await db.close(); }
});

test("long overlapping footprints remain live until their last alternative is processed", async () => {
  const db = new PGlite();
  try {
    await install(db);
    const p = smallProblem(2);
    p.baggageUlds = []; p.fixedLoads = []; p.bulkAreas = [];
    p.groups = [{ id: "A", parentId: null, maximumGrossWeightGrams: 100, maximumBulkVolumeMillilitres: null }];
    p.maximumZeroFuelWeightGrams = 100;
    p.positions = [
      { id: "LONG", kind: "PALLET", groupId: "A", occupiedBayIds: ["A:1", "A:4"], tareWeightGrams: 1, maximumGrossWeightGrams: 8, maximumVolumeMillilitres: 10 },
      { id: "MIDDLE", kind: "CONTAINER", groupId: "A", occupiedBayIds: ["A:2"], tareWeightGrams: 1, maximumGrossWeightGrams: 3, maximumVolumeMillilitres: 10 },
      { id: "LAST", kind: "CONTAINER", groupId: "A", occupiedBayIds: ["A:4"], tareWeightGrams: 1, maximumGrossWeightGrams: 9, maximumVolumeMillilitres: 10 },
    ];
    const r = await run(db, "max_net_cargo_v2", p), exhaustive = await run(db, "exhaustive_net_cargo_v2", p);
    assert.equal(r.arrangement?.cargoNetWeightGrams, 10);
    assert.equal(r.arrangement?.cargoNetWeightGrams, exhaustive.arrangement?.cargoNetWeightGrams);
  } finally { await db.close(); }
});
