// Offline fixture preparation only. Does not invoke either cargo-capacity search.
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { PGlite } from '@electric-sql/pglite';
const root = fileURLToPath(new URL('.', import.meta.url));
const read = name => JSON.parse(readFileSync(root + name, 'utf8'));
const save = (name, value) => writeFileSync(root + name, JSON.stringify(value, null, 2) + '\n');
const sha = text => createHash('sha256').update(text).digest('hex');
const hashFile = name => sha(readFileSync(root + name));
const specification = read('passenger-cases.json');
const frozen = read('../zz9350-2026-10-24/source.json');
const assumptions = read('baggage-assumptions.json');
const density = read('baggage-density.json');
if (!density.carrierWeightKg || density.carrierWeightLb || density.checkedBaggageDensity <= 0) throw Error('Fixture requires known KG baggage density.');
if (assumptions.assumptions.some(row => row.selected?.Average_Bag_Volume !== null)) throw Error('This fixture preparer requires the captured density-based volume assumptions.');
const baseArgs = frozen.databaseArguments;
const baseSolver = read('../zz9350-2026-10-24/solver-input.json');
const spec = frozen.selectedContainer;
const db = new PGlite();
await db.exec('create schema private;');
await db.exec(assumptions.packingFunctionDefinition);
const names = { F: 'First Class', C: 'Business Class', W: 'Premium Economy', Y: 'Economy' };
const commodities = { F: 'BF', C: 'BJ', W: 'BP', Y: 'BY' };
const cases = [], fingerprints = new Map();
try {
  for (const input of specification.cases) {
    const classes = [];
    for (const code of ['F', 'C', 'W', 'Y']) {
      const source = assumptions.assumptions.find(row => row.classCode === code)?.selected;
      if (!source) throw Error(`Missing ${code} baggage assumptions.`);
      const a = { ...source, ...input.overrides?.[code] };
      const passengers = input.passengers[code];
      // PostgreSQL numeric round is retained for piece, weight and density volume
      // derivation; avoid JavaScript floating-point rounding at packing boundaries.
      const r = await db.query(`select round($1::numeric*$2::numeric)::int pieces, round($1::numeric*$3::numeric)::int weight,
        case when $4::numeric is not null then round(round($1::numeric*$2::numeric)*$4::numeric,4)
        else round(round($1::numeric*$3::numeric)/$5::numeric,4) end volume`, [passengers, a.Average_Bags_Per_Passenger, a.Average_Bag_Weight_Per_Passenger, a.Average_Bag_Volume, density.checkedBaggageDensity]);
      const row = r.rows[0];
      classes.push({ classCode: code, className: names[code], commodityCode: a.Baggage_Commodity_Code ?? commodities[code], passengers, bagsPerPassenger: a.Average_Bags_Per_Passenger, weightPerPassenger: a.Average_Bag_Weight_Per_Passenger, plannedPieces: row.pieces, plannedWeight: row.weight, plannedVolume: Number(row.volume) });
    }
    // Match the existing planning chain: aggregate density volume rounded to
    // two decimals, then apportioned by class weight to four decimals.
    const totalWeight = classes.reduce((sum, row) => sum + row.plannedWeight, 0);
    const totalVolume = (await db.query('select round($1::numeric/$2::numeric,2) volume', [totalWeight, density.checkedBaggageDensity])).rows[0].volume;
    for (const row of classes) row.plannedVolume = totalWeight === 0 ? 0 : Number((await db.query('select round($1::numeric*$2::numeric/$3::numeric,4) volume', [totalVolume, row.plannedWeight, totalWeight])).rows[0].volume);
    const targets = (await db.query('select private.a350_baggage_piece_targets($1::jsonb,$2::int,$3::numeric,$4::numeric) targets', [JSON.stringify(classes), spec.ULD_Baggage_Max_Pieces, spec.ULD_Max_Weight - spec.ULD_Tare_Weight, spec.Master_Volume_M3])).rows[0].targets;
    const args = { ...baseArgs, p_baggage_count: targets.length };
    const fingerprint = sha(JSON.stringify(args));
    const duplicate = fingerprints.get(fingerprint) ?? null;
    fingerprints.set(fingerprint, duplicate ?? input.id);
    cases.push({ id: input.id, source: input.source, passengers: input.passengers, baggageClasses: classes, totalPassengers: Object.values(input.passengers).reduce((a, b) => a + b, 0), baggagePieces: classes.reduce((a, b) => a + b.plannedPieces, 0), baggageNetKg: classes.reduce((a, b) => a + b.plannedWeight, 0), baggageUldPieceTargets: targets, reservedBaggageUlds: targets.length,
      reservationBasis: input.overrides ? 'Synthetic unconstrained packing requirement deliberately requested in full, without Bulk diversion or reservation clamping; not an operationally accepted plan' : 'Offline default packing proposal, all proposed ULDs reserved; not an accepted operational booking and not a cargo-capacity result',
      coreInputFingerprint: 'sha256:' + fingerprint, coreInputDuplicateOf: duplicate,
      expectedInfeasibleByCandidateCount: targets.length > baseArgs.p_containers.length,
      databaseArguments: args, solverInput: { ...baseSolver, inputRevision: 'sha256:' + fingerprint, baggageUldCount: targets.length } });
  }
} finally { await db.close(); }
save('prepared-cases.json', { schemaVersion: 1, scope: 'Benchmark input preparation only; no cargo-capacity search or timing', cases });
save('manifest.json', { schemaVersion: 1, aircraftSource: '../zz9350-2026-10-24', aircraftSourceSha256: hashFile('../zz9350-2026-10-24/source.json'), calculationStatus: 'Neither DB cargo-capacity search nor solver executed', caseCount: cases.length, distinctCoreInputCount: fingerprints.size, sourceSha256: Object.fromEntries(['passenger-cases.json', 'baggage-assumptions.json', 'baggage-density.json', 'capture-baggage-assumptions.sql', 'prepare.mjs', 'prepared-cases.json'].map(name => [name, hashFile(name)])), summary: cases.map(({ id, totalPassengers, baggagePieces, baggageNetKg, reservedBaggageUlds, coreInputDuplicateOf, expectedInfeasibleByCandidateCount }) => ({ id, totalPassengers, baggagePieces, baggageNetKg, reservedBaggageUlds, coreInputDuplicateOf, expectedInfeasibleByCandidateCount })) });
console.log(JSON.stringify(read('manifest.json').summary, null, 2));
