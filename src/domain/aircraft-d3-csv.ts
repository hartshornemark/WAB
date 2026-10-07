import { balanceArmFromIndexPerWeightUnit, validIndexPerWeightUnitFormula, type IndexPerWeightUnitFormula } from "@/domain/index-per-weight-unit";
import { bulkHoldIdentity, resolveBulkHoldName } from "@/domain/aircraft-d2";
import type { AircraftD3AtomicBay, AircraftD3Position, AircraftD3UldOption } from "@/domain/aircraft-d3";
import { csvAircraftIdentityError, csvAircraftIdentityHeaders, normaliseCsvAircraftIdentity, type CsvAircraftIdentity } from "@/domain/csv-aircraft-identity";

export type AircraftD3CsvResult = {
  atomicBays: AircraftD3AtomicBay[];
  rows: AircraftD3Position[];
  errors: string[];
  source: CsvAircraftIdentity | null;
  sourceRowCount: number;
  matchedRowCount: number;
};

const legacyHeaders = ["Group ID / Config", "Position Name", "Max Weight", "Centroid", "FWD", "AFT", "Index per wt unit", "Fore-Aft Dimension (in)"];
const routedHeaders = [...csvAircraftIdentityHeaders, "Deck ID", "Hold ID", "Hold Sub Code", "Compartment ID", "Bay ID", "ULD ID / Config", "Max Weight", "Centroid", "FWD", "AFT", "Index per wt unit", "Fore-Aft Dimension (in)"];

export const aircraftD3CsvTemplate = (typeCode: string, subtype: string) => `${routedHeaders.join(",")}\n${normaliseCsvAircraftIdentity(typeCode)},${normaliseCsvAircraftIdentity(subtype)},${",".repeat(routedHeaders.length - 3)}\n`;

function csvRows(text: string) {
  const rows: string[][] = [];
  let row: string[] = [], cell = "", quoted = false;
  for (let i = 0; i < text.length; i += 1) {
    const character = text[i];
    if (quoted) {
      if (character === '"' && text[i + 1] === '"') { cell += '"'; i += 1; }
      else if (character === '"') quoted = false;
      else cell += character;
    } else if (character === '"') quoted = true;
    else if (character === ",") { row.push(cell); cell = ""; }
    else if (character === "\n") { row.push(cell); rows.push(row); row = []; cell = ""; }
    else if (character !== "\r") cell += character;
  }
  row.push(cell);
  if (row.some(value => value.trim())) rows.push(row);
  return rows;
}

const clean = (value: string | undefined) => String(value ?? "").trim();
const normal = (value: string) => value.toLowerCase().replace(/[^a-z0-9]+/g, "");
const identity = (value: string) => clean(value).toUpperCase().replace(/[^A-Z0-9-]/g, "");
const side = (positionId: string) => positionId.endsWith("L") ? "L" : positionId.endsWith("R") ? "R" : "B";

function numeric(value: string | undefined, label: string, line: number, errors: string[]) {
  const parsed = Number(clean(value));
  if (!clean(value) || !Number.isFinite(parsed)) {
    errors.push(`Line ${line}: ${label} must be a number.`);
    return null;
  }
  return parsed;
}

function sameNumber(left: number | null, right: number | null) {
  return left === right || (left !== null && right !== null && Math.abs(left - right) < 1e-9);
}

export function parseAircraftD3Csv(
  text: string,
  compartments: string[] = [],
  uldOptions: AircraftD3UldOption[] = [],
  geometry?: { formula?: IndexPerWeightUnitFormula | null; lengthUnit: string },
  route?: { holdId: string; deckName?: string; typeCode?: string; subtype?: string },
): AircraftD3CsvResult {
  const records = csvRows(text.replace(/^\uFEFF/, ""));
  const errors: string[] = [];
  if (!records.length) return { atomicBays: [], rows: [], errors: ["The CSV file is empty."], source: null, sourceRowCount: 0, matchedRowCount: 0 };
  const sourceRowCount = records.slice(1).filter(row => row.some(value => value.trim())).length;
  let matchedRowCount = 0;

  const actualHeaders = records[0].map(normal);
  const routed = ["Deck ID", "Hold ID", "Hold Sub Code", "Compartment ID", "Bay ID", "ULD ID / Config"].some(header => actualHeaders.includes(normal(header)));
  const expectedHeaders = routed ? routedHeaders : legacyHeaders;
  const optionalHeaders = ["Centroid", "FWD", "AFT", "Fore-Aft Dimension (in)"];
  const missing = expectedHeaders.filter(header => !optionalHeaders.includes(header) && !actualHeaders.includes(normal(header)));
  if (route?.typeCode && route?.subtype) {
    for (const header of csvAircraftIdentityHeaders) if (!actualHeaders.includes(normal(header))) missing.unshift(header);
  }
  if (missing.length) return { atomicBays: [], rows: [], errors: [`Missing AHM565 columns: ${[...new Set(missing)].join(", ")}. Download a new template for this aircraft.`], source: null, sourceRowCount, matchedRowCount };

  const column = (row: string[], name: string) => row[actualHeaders.indexOf(normal(name))];
  const inferredCompartmentFor = (position: string) => [...compartments].sort((a,b) => b.length-a.length).find(id => position.startsWith(id)) ?? "";
  const byIdentity = new Map(uldOptions.map(option => [option.code, option]));

  type Source = {
    line: number;
    positionId: string;
    compartmentId: string;
    uldCode: string;
    uldType: string;
    baseCode: string | null;
    maxWeight: number | null;
    centroid: number | null;
    from: number | null;
    to: number | null;
    index: number | null;
  };
  const sourceByPositionAndType = new Map<string, Source>();
  let source: CsvAircraftIdentity | null = null;

  records.slice(1).forEach((row, rowIndex) => {
    const line = rowIndex + 2;
    if (route?.typeCode && route?.subtype) {
      const rowSource = { typeCode: normaliseCsvAircraftIdentity(column(row, "Aircraft Type IATA")), subtype: normaliseCsvAircraftIdentity(column(row, "Series/Sub-Type")) };
      const identityError = csvAircraftIdentityError(rowSource, { typeCode: route.typeCode, subtype: route.subtype }, line);
      if (identityError) { errors.push(identityError); return; }
      if (source && (source.typeCode !== rowSource.typeCode || source.subtype !== rowSource.subtype)) { errors.push(`Line ${line}: aircraft identity differs from earlier rows.`); return; }
      source = rowSource;
    }
    let explicitCompartment = "";
    if (routed) {
      const deckId = identity(column(row, "Deck ID"));
      const holdId = identity(column(row, "Hold ID"));
      const subCode = identity(column(row, "Hold Sub Code"));
      explicitCompartment = identity(column(row, "Compartment ID"));
      const resolved = subCode ? resolveBulkHoldName(holdId, subCode) : holdId;
      if (!deckId || !holdId || !resolved) {
        errors.push(`Line ${line}: check Deck ID, Hold ID and Hold Sub Code.`);
        return;
      }
      if (route) {
        const [targetDeck, ...targetNameParts] = route.holdId.split(":");
        const targetName = targetNameParts.join(":");
        const targetFamily = bulkHoldIdentity(targetName).holdId;
        const sameDeck = [targetDeck.toUpperCase(), route.deckName?.toUpperCase()].filter(Boolean).includes(deckId);
        // D2 may store a complete compartment under one optional sub-code
        // (for example ALA), while D3 uses ALF/ALM/ALA to describe successive
        // bay groups within that same compartment. Route by deck, parent hold
        // family and the compartment actually saved on D2. The sub-code is
        // descriptive here; it must not make valid bays disappear.
        if (!sameDeck || targetFamily !== holdId || !compartments.includes(explicitCompartment)) return;
      }
      if (!explicitCompartment || !compartments.includes(explicitCompartment)) {
        errors.push(`Line ${line}: Compartment ID must belong to the selected D2 hold.`);
        return;
      }
      matchedRowCount += 1;
    }
    const uldIdentity = identity(column(row, routed ? "ULD ID / Config" : "Group ID / Config"));
    const names = clean(column(row, routed ? "Bay ID" : "Position Name")).toUpperCase().split(/[,;/]+/).map(value => value.trim()).filter(Boolean);
    if (!routed && names.length && !names.some(position => inferredCompartmentFor(position))) return;
    if (!routed) matchedRowCount += 1;
    const maxWeight = numeric(column(row, "Max Weight"), "Max Weight", line, errors);
    const optionalNumber = (name: string) => clean(column(row, name)) ? numeric(column(row, name), name, line, errors) : null;
    let centroid = optionalNumber("Centroid");
    let from = optionalNumber("FWD");
    let to = optionalNumber("AFT");
    const index = numeric(column(row, "Index per wt unit"), "Index per wt unit", line, errors);

    if (!uldIdentity || !names.length) {
      errors.push(`Line ${line}: ULD identity and Position Name are required.`);
      return;
    }

    const option = byIdentity.get(uldIdentity);
    if (!option) {
      errors.push(`Line ${line}: ${uldIdentity} is not recognised in the Master ULD list.`);
      return;
    }
    if (!option.adopted) {
      errors.push(`Line ${line}: ${uldIdentity} must first be selected on B5 for this aircraft.`);
    }
    if (!clean(column(row, "Centroid")) && index !== null && validIndexPerWeightUnitFormula(geometry?.formula)) {
      centroid = balanceArmFromIndexPerWeightUnit(index, geometry.formula);
    }
    const inchesToUnit: Record<string, number> = { M: 0.0254, CM: 2.54, IN: 1, FT: 1 / 12 };
    const factor = inchesToUnit[geometry?.lengthUnit ?? ""];
    const dimensionText = clean(column(row, "Fore-Aft Dimension (in)"));
    const runningDimension = dimensionText ? numeric(dimensionText, "Fore-Aft Dimension (in)", line, errors) : option.baseLength;
    if (dimensionText && runningDimension !== null && runningDimension <= 0) errors.push(`Line ${line}: Fore-Aft Dimension (in) must be greater than zero.`);
    const length = runningDimension !== null && runningDimension > 0 && factor ? runningDimension * factor : null;
    if (centroid === null) errors.push(`Line ${line}: provide Centroid or save C4 so it can be calculated from Index per wt unit.`);
    if (centroid !== null && length !== null) {
      if (!clean(column(row, "FWD"))) from = Math.round((centroid - length / 2) * 1e6) / 1e6;
      if (!clean(column(row, "AFT"))) to = Math.round((centroid + length / 2) * 1e6) / 1e6;
    }
    if (from === null || to === null) errors.push(`Line ${line}: provide FWD/AFT or a Fore-Aft Dimension (in) / ULD base length and C1 length unit for calculation.`);
    if (from !== null && centroid !== null && to !== null && !(from <= centroid && centroid <= to)) {
      errors.push(`Line ${line}: FWD, Centroid and AFT are not in order.`);
    }

    names.forEach(positionId => {
      if (!/^[A-Z0-9]{1,6}$/.test(positionId)) {
        errors.push(`Line ${line}: Position ${positionId} is invalid.`);
        return;
      }
      const compartmentId = routed ? explicitCompartment : inferredCompartmentFor(positionId);
      if (!compartments.includes(compartmentId)) return;

      const candidate: Source = { line, positionId, compartmentId, uldCode: option.code, uldType: option.type, baseCode: option.baseCode, maxWeight, centroid, from, to, index };
      const key = `${positionId}\0${option.code}`;
      const existing = sourceByPositionAndType.get(key);
      if (!existing) {
        sourceByPositionAndType.set(key, candidate);
        return;
      }
      const agrees = sameNumber(existing.maxWeight, maxWeight) && sameNumber(existing.centroid, centroid)
        && sameNumber(existing.from, from) && sameNumber(existing.to, to) && sameNumber(existing.index, index);
      if (!agrees) errors.push(`Lines ${existing.line} and ${line}: ${positionId} / ${option.code} is duplicated with different limits.`);
    });
  });

  const sources = [...sourceByPositionAndType.values()];
  const bayMap = new Map<string, AircraftD3AtomicBay>();
  for (const source of sources) {
    // Single-position holds need physical bays too (e.g. A321 positions 11, 12).
    // Where paired bays exist in a compartment, wider alternatives occupy those bays.
    const hasPairedBays = sources.some(item => item.compartmentId === source.compartmentId && /[LR]$/.test(item.positionId));
    if ((hasPairedBays && !/[LR]$/.test(source.positionId)) || source.centroid === null) continue;
    const current = bayMap.get(source.positionId);
    if (current && !(sameNumber(current.balanceFrom, source.from) && sameNumber(current.balanceCentroid, source.centroid) && sameNumber(current.balanceTo, source.to))) {
      errors.push(`Position ${source.positionId} has inconsistent FWD/AFT limits.`);
    } else if (!current) {
      bayMap.set(source.positionId, {
        id: source.positionId,
        compartmentId: source.compartmentId,
        lateralCentroid: null,
        lateralFrom: null,
        lateralTo: null,
        balanceCentroid: source.centroid,
        balanceFrom: source.from,
        balanceTo: source.to,
        colour: null,
      });
    }
  }

  const atomicBays = [...bayMap.values()].sort((left, right) =>
    (left.balanceCentroid ?? 0) - (right.balanceCentroid ?? 0) || left.id.localeCompare(right.id));
  const rows: AircraftD3Position[] = sources.map(source => {
    const positionSide = side(source.positionId);
    const occupiedBayIds = atomicBays.filter(bay =>
      bay.compartmentId === source.compartmentId && bay.balanceFrom !== null && bay.balanceTo !== null && source.from !== null && source.to !== null
      && bay.balanceFrom < source.to && bay.balanceTo > source.from
      && (positionSide === "B" || side(bay.id) === positionSide)).map(bay => bay.id);
    if (!occupiedBayIds.length) errors.push(`Line ${source.line}: ${source.positionId} does not overlap an Atomic Bay.`);
    return {
      rowType: "POSITION",
      positionId: source.positionId,
      compartmentId: source.compartmentId,
      uldCode: source.uldCode,
      uldType: source.uldType,
      uldBaseCode: source.baseCode,
      groupId: null,
      occupiedBayIds,
      maxWeight: source.maxWeight,
      volume: null,
      lateralCentroid: null,
      lateralFrom: null,
      lateralTo: null,
      balanceCentroid: source.centroid,
      balanceFrom: source.from,
      balanceTo: source.to,
      indexPerWeightUnit: source.index,
      colour: null,
    };
  });

  if (!sources.length) errors.push(`No positions in this CSV belong to Compartments ${compartments.join(", ") || "configured for this hold"}.`);
  if (!atomicBays.length) errors.push("No physical positions were found for this hold.");
  return { atomicBays, rows, errors: [...new Set(errors)], source, sourceRowCount, matchedRowCount };
}
