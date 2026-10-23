// Input preparation only: never invoke a cargo-capacity calculation here.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { validateCargoCapacityProblem } from '../../../../src/domain/cargo-capacity.ts';

const root = fileURLToPath(new URL('.', import.meta.url));
const read = name => JSON.parse(readFileSync(root + name, 'utf8'));
const hash = value => createHash('sha256').update(value).digest('hex');
const fileHash = name => hash(readFileSync(root + name));
const encode = value => JSON.stringify(value, null, 2) + '\n';
const check = process.argv.includes('--check');
const save = (name, value) => {
  const text = encode(value);
  if (check) assert.equal(readFileSync(root + name, 'utf8'), text, `Changed ${name}`);
  else writeFileSync(root + name, text);
};
const kg = value => { assert.equal(typeof value, 'number'); assert(Number.isSafeInteger(value * 1000)); return value * 1000; };
const ml = value => { assert.equal(typeof value, 'number'); const n = Math.round(value * 1_000_000); assert(Math.abs(n - value * 1_000_000) < 0.001); return n; };
const frozen = read('../zz9350-2026-10-24/source.json');
const old = read('../passenger-scenarios/prepared-cases.json');
const source = read('source.json');
const verification = read('verification-source.json');
const flight = source.flight;

// Reject silent drift of the original aircraft/ULD/footprint snapshot.
assert.deepEqual(source.holds, frozen.holds);
assert.equal(source.positions.length, frozen.candidateSourceRows.length);
for (const row of source.positions) {
  const original = frozen.candidateSourceRows.find(p => p.ULD_Position_UUID === row.ULD_Position_UUID);
  for (const [key, value] of Object.entries(row)) assert.deepEqual(value, original?.[key], `Position drift ${row.ULD_Position_UUID}/${key}`);
  assert.deepEqual(verification.occupancy.find(p => p.positionId === row.ULD_Position_UUID)?.bays, original.bays);
}
for (const original of [frozen.selectedContainer, frozen.selectedPallet]) {
  const current = source.specifications.find(s => s.ULD_ID === original.ULD_ID);
  for (const [key, value] of Object.entries(current)) assert.deepEqual(value, original[key]);
  assert.equal(verification.masterVolumes.find(s => s.ULD_ID === original.ULD_ID).ULD_Volume, original.Master_Volume_M3);
}
for (const key of ['Carrier_IATA', 'Aircraft_Type_IATA', 'Aircraft_Series_Subtype', 'Aircraft_Configuration']) assert.equal(flight[key], frozen.flight[key]);
assert.equal(flight.Passenger_Weight_Basis, 'STANDARD');
assert.equal(source.passengerByClass.length, 0);
assert(source.units.Kilograms && !source.units.Pounds);
assert.equal(frozen.units.Weight_Unit, 'KG');
assert.equal(frozen.units.Volume_Unit, 'M3');
assert.equal(source.aircraft.Start_Weight_Principle, 'DRY_OPERATING_WEIGHT');
assert.equal(source.fuelConfigurations.length, 0);
assert(source.crew.length && source.pantry.length);
for (const row of [...source.holds, ...source.compartments, ...source.areas, ...source.positions]) {
  assert.deepEqual(row.Applicable_Fuel_Configurations, []);
  assert.deepEqual(row.Fuel_Configuration_Overrides, []);
}
const aircraft = source.aircraft;
const fleet = source.fleet.filter(x => x.Aircraft_Registration.trim() === flight.Aircraft_Registration.trim());
assert.equal(fleet.length, 1);
// Match the saved freight calculation: code adjustment is one maximum, not a
// sum over repeated crew-location rows. Null adjustments are not defaulted here.
const crewAdjustment = Math.max(...source.crew.map(x => { assert.equal(typeof x.DOW_Weight_Adjustment, 'number'); return x.DOW_Weight_Adjustment; }));
const pantryAdjustment = Math.max(...source.pantry.map(x => { assert.equal(typeof x.DOW_Weight_Adjustment, 'number'); return x.DOW_Weight_Adjustment; }));
const effectiveDow = fleet[0].Dry_Operating_Weight + crewAdjustment + pantryAdjustment;
const limits = source.limitingWeights.filter(x => x.Table_Name === 'ALL' && x.Carrier_Variant_Code === flight.Aircraft_Series_Subtype && (x.Aircraft_Registration === null || x.Aircraft_Registration.trim() === flight.Aircraft_Registration.trim()));
limits.sort((a, b) => Number(b.Aircraft_Registration !== null) - Number(a.Aircraft_Registration !== null));
assert(limits.length <= 1 || (limits[0].Aircraft_Registration !== null && limits[1].Aircraft_Registration === null));
const maximumZfw = limits[0]?.Zero_Fuel_Weight ?? aircraft.MZFW;
const passenger = source.passengerBaseline;
assert.equal(typeof passenger.Adult, 'number');
assert.equal(passenger.Passenger_Weights_Include_Handbaggage, true);
const passengerKg = passenger.Adult; // Adult planning average; no age/sex mix supplied.

const holdId = h => `HOLD:${h}`;
const compartmentId = (h, c) => `COMPARTMENT:${h}:${c}`;
const areaId = a => `${a.Hold_Name_ID}:${a.Compartment_ID}:${a.Area_ID}`;
const bulkHolds = new Set(source.holds.filter(h => h.Hold_Type === 'BLK').map(h => h.Hold_Name_ID));
const groups = source.holds.map(h => ({ id: holdId(h.Hold_Name_ID), parentId: null,
  maximumGrossWeightGrams: kg(h.Hold_MAX_Weight), maximumBulkVolumeMillilitres: h.Hold_MAX_Volume === null ? null : ml(h.Hold_MAX_Volume) }));
for (const c of source.compartments) {
  assert(source.holds.some(h => h.Hold_Name_ID === c.Hold_Name_ID));
  groups.push({ id: compartmentId(c.Hold_Name_ID, c.Compartment_ID), parentId: holdId(c.Hold_Name_ID), maximumGrossWeightGrams: kg(c.Compartment_Max_Weight), maximumBulkVolumeMillilitres: c.Compartment_Max_Volume === null ? null : ml(c.Compartment_Max_Volume) });
}
const bulkAreas = source.areas.map(a => {
  assert(bulkHolds.has(a.Hold_Name_ID));
  assert(groups.some(g => g.id === compartmentId(a.Hold_Name_ID, a.Compartment_ID)));
  return { id: areaId(a), groupId: compartmentId(a.Hold_Name_ID, a.Compartment_ID), maximumGrossWeightGrams: kg(a.Area_Max_Weight), maximumVolumeMillilitres: ml(a.Area_Max_Volume) };
});
assert(bulkAreas.length > 0);
const positions = frozen.candidateSourceRows.map(p => {
  const spec = p.ULD_Code.trim() === frozen.selectedContainer.ULD_ID ? frozen.selectedContainer : frozen.selectedPallet;
  assert.equal(p.ULD_Configuration_Code, flight.Aircraft_Configuration);
  const groupId = compartmentId(p.Hold_Name_ID, p.Compartment_ID);
  assert(groups.some(g => g.id === groupId));
  return { id: p.ULD_Position_UUID, kind: spec === frozen.selectedPallet ? 'PALLET' : 'CONTAINER', groupId, occupiedBayIds: p.bays,
    tareWeightGrams: kg(spec.ULD_Tare_Weight), maximumGrossWeightGrams: kg(Math.min(spec.ULD_Max_Weight, p.ULD_Position_Max_Weight)),
    maximumVolumeMillilitres: ml(p.ULD_Position_Volume === null ? spec.Master_Volume_M3 : Math.min(p.ULD_Position_Volume, spec.Master_Volume_M3)) };
});
const compatible = positions.filter(p => p.kind === 'CONTAINER').map(p => p.id);

// Preserve the frozen packing targets and class forecasts. All seven captured
// cases have the same 15 kg per bag, including the explicit infeasible override.
// Split each class forecast over its bags; distribute sub-millilitre residuals
// deterministically across ULDs, preserving the exact total class volume.
const cases = [];
if (!check) mkdirSync(root + 'inputs', { recursive: true });
for (const c of old.cases) {
  const remaining = c.baggageClasses.map(row => ({ ...row, remaining: row.plannedPieces }));
  const bagRequirements = [];
  for (const [i, target] of c.baggageUldPieceTargets.entries()) {
    let pieces = target, netKg = 0, volumeMl = 0;
    const contents = [];
    for (const row of remaining) {
      if (!pieces) break;
      const take = Math.min(pieces, row.remaining);
      if (!take) continue;
      const net = row.plannedWeight * take / row.plannedPieces;
      const volume = ml(row.plannedVolume) * take / row.plannedPieces;
      netKg += net; volumeMl += volume;
      contents.push({ commodityCode: row.commodityCode, pieces: take, netWeightGrams: kg(net) });
      pieces -= take; row.remaining -= take;
    }
    assert.equal(pieces, 0);
    bagRequirements.push({ id: `${c.id}:BAG:${String(i + 1).padStart(2, '0')}`, pieces: target, contents, netWeightGrams: kg(netKg), unroundedVolume: volumeMl });
  }
  assert(remaining.every(r => r.remaining === 0));
  const totalMl = c.baggageClasses.reduce((sum, row) => sum + ml(row.plannedVolume), 0);
  const volumes = bagRequirements.map(b => Math.floor(b.unroundedVolume));
  const fractions = bagRequirements.map((b, i) => ({ i, fraction: b.unroundedVolume - volumes[i] })).sort((a, b) => b.fraction - a.fraction || a.i - b.i);
  const residual = totalMl - volumes.reduce((a, b) => a + b, 0);
  assert(residual >= 0 && residual <= fractions.length);
  for (let i = 0; i < residual; i++) volumes[fractions[i].i]++;
  const baggageUlds = bagRequirements.map((b, i) => ({ id: b.id, netWeightGrams: b.netWeightGrams, volumeMillilitres: volumes[i], compatiblePositionIds: compatible }));
  assert.equal(baggageUlds.reduce((s, b) => s + b.netWeightGrams, 0), kg(c.baggageNetKg));
  assert.equal(baggageUlds.length, c.reservedBaggageUlds);
  const problem = { mode: 'CARGO_CAPACITY', aircraftType: '359', rulesVersion: 'A350_MAX_NET_CARGO_V2', inputRevision: 'pending', timeLimitSeconds: 2,
    maximumZeroFuelWeightGrams: kg(maximumZfw), dryOperatingWeightGrams: kg(effectiveDow), passengerWeightGrams: kg(c.totalPassengers * passengerKg), cargoDensityGramsPerM3: kg(source.units.Density_General_Cargo),
    positions, groups, bulkAreas, baggageUlds, fixedLoads: [] };
  problem.inputRevision = 'sha256:' + hash(JSON.stringify({ ...problem, inputRevision: undefined }));
  validateCargoCapacityProblem(problem);
  const filename = `inputs/${c.id}.json`;
  save(filename, problem);
  cases.push({ id: c.id, passengers: c.passengers, totalPassengers: c.totalPassengers, passengerWeightGrams: problem.passengerWeightGrams,
    baggageNetWeightGrams: kg(c.baggageNetKg), baggageUldCount: baggageUlds.length, baggageTareWeightGrams: kg(frozen.selectedContainer.ULD_Tare_Weight * baggageUlds.length), baggageVolumeMillilitres: totalMl,
    baggageUldContents: bagRequirements.map((b, i) => ({ id: b.id, pieces: b.pieces, contents: b.contents, netWeightGrams: b.netWeightGrams, volumeMillilitres: volumes[i] })),
    fixedReservationScope: 'Synthetic offer baseline: all proposed baggage is in ULDs; no Bulk baggage or other reserved load. Existing flight freight and accepted accommodation are not overlaid.',
    expectedInfeasibleByCandidateCount: c.expectedInfeasibleByCandidateCount,
    databaseInput: filename, solverInput: filename, inputRevision: problem.inputRevision, inputSha256: hash(encode(problem)) });
}
const sources = ['source.json', 'capture.sql', 'verification-source.json', 'verification-capture.sql', 'prepare.mjs', 'README.md', '../zz9350-2026-10-24/source.json', '../passenger-scenarios/prepared-cases.json', '../passenger-scenarios/passenger-cases.json', '../passenger-scenarios/baggage-assumptions.json', '../passenger-scenarios/baggage-density.json'];
save('manifest.json', { schemaVersion: 2, rulesVersion: 'A350_MAX_NET_CARGO_V2', status: 'Inputs prepared and validated only; no capacity result comparison or timing run',
  sourceCaptureAt: source.capturedAt, verificationCaptureAt: verification.capturedAt,
  snapshotPolicy: 'Original frozen passenger, baggage and aircraft inputs plus separately timestamped V2 enrichment; original holds/specs/positions/occupancy and master volumes verified unchanged. Not one historical database transaction.',
  weightProvenance: { registration: flight.Aircraft_Registration, flightVersion: flight.Version, maximumZfwKg: maximumZfw, maximumZfwSource: limits.length ? 'Aircraft_Limiting_Weight_Values: ALL / subtype / matching registration or generic' : 'Basic_Aircraft_Data.MZFW', baseDowKg: fleet[0].Dry_Operating_Weight, crewAdjustmentKg: crewAdjustment, pantryAdjustmentKg: pantryAdjustment, effectiveDowKg: effectiveDow, passengerPlanningKg: passengerKg, passengerSource: 'Carrier_Passenger_Weights_ALLFLIGHTS.Adult; hand baggage included', cargoDensityKgPerM3: source.units.Density_General_Cargo },
  timeLimitPolicy: '2 seconds retained as an explicit prototype setting, not an agreed Step 3 or timing execution budget; any change requires a new input revision for both components.',
  sourceSha256: Object.fromEntries(sources.map(name => [name, fileHash(name)])), cases });
const sealed = [...sources.filter(n => !n.startsWith('../')), ...cases.map(c => c.databaseInput), 'manifest.json'];
const sums = sealed.map(name => `${fileHash(name)}  ${name}`).join('\n') + '\n';
if (check) assert.equal(readFileSync(root + 'SHA256SUMS', 'utf8'), sums);
else writeFileSync(root + 'SHA256SUMS', sums);
console.log(`${check ? 'Verified' : 'Prepared'} ${cases.length} V2 input packages; no capacity calculation executed.`);
