import { AircraftD2Invalid, resolveBulkHoldName, validateAircraftD2Section, type AircraftD2DeckType, type AircraftD2HoldRow } from "@/domain/aircraft-d2";
import type { FuelConfigurationOption } from "@/domain/fuel-configuration-scope";
import { balanceArmFromIndexPerWeightUnit, validIndexPerWeightUnitFormula, type IndexPerWeightUnitFormula } from "@/domain/index-per-weight-unit";

const headers = ["Aircraft Type IATA", "Series/Sub-Type", "Deck ID", "Hold Type", "Hold ID", "Hold Sub Code", "Compartment ID", "Area ID", "MAXWT", "VOL", "BA Centroid", "BA FWD", "BA AFT", "Index Per Weight Unit", "Door"];
export const aircraftD2CsvTemplate = (typeCode:string,subtype:string) => `${headers.join(",")}\n${[typeCode.toUpperCase(),subtype.toUpperCase(),...Array(headers.length-2).fill("")].join(",")}\n`;
export type AircraftD2CsvIdentity = { typeCode: string; subtype: string };
export type AircraftD2CsvResult = { rows: AircraftD2HoldRow[]; errors: string[]; sections: Array<"BULK"|"ULD">; source: AircraftD2CsvIdentity | null };

function csvRows(text: string) {
  const rows: string[][] = [];
  let row: string[] = [], cell = "", quoted = false;
  for (let index = 0; index < text.length; index += 1) {
    const character = text[index];
    if (quoted) {
      if (character === '"' && text[index + 1] === '"') { cell += '"'; index += 1; }
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
const identifier = (value: string | undefined) => clean(value).toUpperCase();
function numberValue(value: string | undefined, label: string, line: number, errors: string[], required = true) {
  const text = clean(value);
  if (!text && !required) return null;
  const parsed = Number(text);
  if (!text || !Number.isFinite(parsed)) {
    errors.push(`Line ${line}: ${label} must be a number${required ? "" : " or blank"}.`);
    return null;
  }
  return parsed;
}

export function parseAircraftD2Csv(text: string, deckTypes: AircraftD2DeckType[], fuelConfigurations: FuelConfigurationOption[] = [], balanceFormula?: IndexPerWeightUnitFormula | null, expected?: AircraftD2CsvIdentity): AircraftD2CsvResult {
  const records = csvRows(text.replace(/^\uFEFF/, ""));
  const errors: string[] = [];
  if (!records.length) return { rows: [], errors: ["The CSV file is empty."], sections: [], source: null };
  const actualHeaders = records[0].map(normal);
  const missing = headers.filter(header => !actualHeaders.includes(normal(header)));
  if (missing.length) return { rows: [], errors: [`Missing D2 columns: ${missing.join(", ")}. Download a new template for this aircraft.`], sections: [], source: null };
  const column = (row: string[], name: string) => row[actualHeaders.indexOf(normal(name))];
  const deckCodes = new Map(deckTypes.map(deck => [deck.code.toUpperCase(), deck.code]));
  const deckNames = new Map(deckTypes.map(deck => [deck.name.toUpperCase(), deck.code]));
  const holds = new Map<string, AircraftD2HoldRow>();
  const holdDoors = new Map<string, boolean>();
  const holdLines = new Map<string, number>();
  const areaLines = new Map<string, number>();
  const areaMetrics = new Map<string, Array<{ maxWeight: number; maxVolume: number | null; centroid: number | null; from: number | null; to: number | null; index: number }>>();
  const sections = new Set<"BULK"|"ULD">();
  let source: AircraftD2CsvIdentity | null = null;

  records.slice(1).forEach((record, recordIndex) => {
    const line = recordIndex + 2;
    if (!record.some(value => value.trim())) return;
    const sourceTypeCode = identifier(column(record, "Aircraft Type IATA"));
    const sourceSubtype = identifier(column(record, "Series/Sub-Type"));
    if (!/^[A-Z0-9]{3}$/.test(sourceTypeCode) || !/^[A-Z0-9]{1,4}$/.test(sourceSubtype)) {
      errors.push(`Line ${line}: Aircraft Type IATA and Series/Sub-Type are required.`);
      return;
    }
    if (!source) source = { typeCode: sourceTypeCode, subtype: sourceSubtype };
    else if (source.typeCode !== sourceTypeCode || source.subtype !== sourceSubtype) {
      errors.push(`Line ${line}: every row must identify the same aircraft as line 2 (${source.typeCode}-${source.subtype}).`);
      return;
    }
    if (expected && (sourceTypeCode !== expected.typeCode.toUpperCase() || sourceSubtype !== expected.subtype.toUpperCase())) {
      errors.push(`Line ${line}: CSV aircraft ${sourceTypeCode}-${sourceSubtype} does not match this page ${expected.typeCode.toUpperCase()}-${expected.subtype.toUpperCase()}. Nothing has been imported.`);
      return;
    }
    const deckText = identifier(column(record, "Deck ID"));
    const holdTypeText = identifier(column(record, "Hold Type"));
    const holdType = holdTypeText === "BLK" || holdTypeText === "BULK" ? "BLK" : holdTypeText === "ULD" ? "ULD" : null;
    const holdId = identifier(column(record, "Hold ID"));
    const subCode = identifier(column(record, "Hold Sub Code"));
    const name = holdType === "ULD" ? (subCode || holdId) : resolveBulkHoldName(holdId, subCode);
    const deckCode = deckCodes.get(deckText) ?? deckNames.get(deckText) ?? "";
    if (!holdId) {
      errors.push(`Line ${line}: Hold ID is required.`);
      return;
    }
    if (!holdType) {
      errors.push(`Line ${line}: Hold Type must be BLK or ULD.`);
      return;
    }
    sections.add(holdType === "BLK" ? "BULK" : "ULD");
    if (!name || (holdType === "ULD" && !/^[A-Z]{3}$/.test(name))) {
      errors.push(`Line ${line}: use FWD with optional FLF/FLM/FLA, AFT with optional ALF/ALM/ALA, or ALB without a sub-code.`);
      return;
    }
    if (!deckCode) {
      errors.push(`Line ${line}: Deck ID must match a D2 deck code or name.`);
      return;
    }
    const holdKey = `${holdType}:${deckCode}:${name}`;
    const doorText = identifier(column(record, "Door"));
    const hasDoor = ["Y", "YES"].includes(doorText) ? true : ["N", "NO"].includes(doorText) ? false : null;
    if (hasDoor === null) errors.push(`Line ${line}: Door must be Y or N.`);
    else if (holdDoors.has(holdKey) && holdDoors.get(holdKey) !== hasDoor) errors.push(`Line ${line}: repeat the same Door Y/N value for Hold ${name}.`);
    else holdDoors.set(holdKey, hasDoor);
    const compartmentId = identifier(column(record, "Compartment ID"));
    const areaId = identifier(column(record, "Area ID"));
    if (areaId && !compartmentId) errors.push(`Line ${line}: Area ID requires a Compartment ID.`);
    if (holdType === "ULD" && !compartmentId) errors.push(`Line ${line}: a ULD Hold requires a Compartment ID.`);
    if (holdType === "ULD" && areaId) errors.push(`Line ${line}: ULD Holds use Bays on D3, so Area ID must be blank.`);

    const maxWeight = numberValue(column(record, "MAXWT"), "MAXWT", line, errors);
    const maxVolume = numberValue(column(record, "VOL"), "VOL", line, errors, false);
    const suppliedCentroid = numberValue(column(record, "BA Centroid"), "BA Centroid", line, errors, false);
    const from = numberValue(column(record, "BA FWD"), "BA FWD", line, errors, false);
    const to = numberValue(column(record, "BA AFT"), "BA AFT", line, errors, false);
    const index = numberValue(column(record, "Index Per Weight Unit"), "Index Per Weight Unit", line, errors);
    const centroid = suppliedCentroid === null && index !== null && validIndexPerWeightUnitFormula(balanceFormula)
      ? balanceArmFromIndexPerWeightUnit(index, balanceFormula)
      : suppliedCentroid;
    if ((from === null) !== (to === null)) errors.push(`Line ${line}: complete both BA FWD and BA AFT, or leave both blank.`);

    if (holdType === "ULD") {
      let hold = holds.get(holdKey);
      if (!hold) {
        hold = { id: `${deckCode}:${name}`, name, holdType: "ULD", deckCode, hasDoor, maxWeight, maxVolume, lateralCentroid: null, lateralFrom: null, lateralTo: null, balanceCentroid: centroid, balanceFrom: from, balanceTo: to, indexPerWeightUnit: index, compartments: [], configurationCodes: [], configurationOverrides: [] };
        holds.set(holdKey, hold);
        holdLines.set(holdKey, line);
      } else if ([hold.maxWeight,hold.maxVolume,hold.balanceCentroid,hold.balanceFrom,hold.balanceTo,hold.indexPerWeightUnit].some((value,indexValue)=>value!==[maxWeight,maxVolume,centroid,from,to,index][indexValue])) {
        errors.push(`Lines ${holdLines.get(holdKey)} and ${line}: repeat identical ULD Hold values for ${name}.`);
      }
      if (compartmentId) {
        if (hold.compartments.some(item=>item.id===compartmentId)) errors.push(`Line ${line}: Compartment ${compartmentId} is duplicated in ULD Hold ${name}.`);
        else hold.compartments.push({id:compartmentId,areas:[],configurationCodes:[],configurationOverrides:[]});
      }
      return;
    }

    if (!compartmentId) {
      if (holds.has(holdKey)) {
        errors.push(`Lines ${holdLines.get(holdKey)} and ${line}: Hold ${deckCode}:${name} has more than one hold-level row.`);
        return;
      }
      holds.set(holdKey, { id: `${deckCode}:${name}`, name, holdType: "BLK", deckCode, hasDoor, maxWeight, maxVolume, lateralCentroid: null, lateralFrom: null, lateralTo: null, balanceCentroid: centroid, balanceFrom: from, balanceTo: to, indexPerWeightUnit: index, compartments: [], configurationCodes: [], configurationOverrides: [] });
      holdLines.set(holdKey, line);
      return;
    }

    let hold = holds.get(holdKey);
    if (!hold) {
      hold = { id: `${deckCode}:${name}`, name, holdType: "BLK", deckCode, hasDoor, maxWeight: null, maxVolume: null, lateralCentroid: null, lateralFrom: null, lateralTo: null, balanceCentroid: null, balanceFrom: null, balanceTo: null, indexPerWeightUnit: null, compartments: [], configurationCodes: [], configurationOverrides: [] };
      holds.set(holdKey, hold);
    }
    let compartment = hold.compartments.find(item => item.id === compartmentId);
    if (!compartment) {
      compartment = { id: compartmentId, areas: [], configurationCodes: [], configurationOverrides: [] };
      hold.compartments.push(compartment);
    }
    if (!areaId) return;
    const areaKey = `${holdKey}:${compartmentId}:${areaId}`;
    if (areaLines.has(areaKey)) {
      errors.push(`Lines ${areaLines.get(areaKey)} and ${line}: Area ${areaId} is duplicated in Compartment ${compartmentId}.`);
      return;
    }
    areaLines.set(areaKey, line);
    compartment.areas.push({ id: areaId, maxWeight, maxVolume, indexPerWeightUnit: index, configurationCodes: [], configurationOverrides: [] });
    if (maxWeight !== null && index !== null) areaMetrics.set(holdKey, [...(areaMetrics.get(holdKey) ?? []), { maxWeight, maxVolume, centroid, from, to, index }]);
  });

  for (const [holdKey, hold] of holds) {
    if (holdLines.has(holdKey)) continue;
    const metrics = areaMetrics.get(holdKey) ?? [];
    if (!metrics.length) continue;
    const totalWeight = metrics.reduce((total, item) => total + item.maxWeight, 0);
    const weighted = (values: Array<number | null>) => values.every(value => value !== null)
      ? Math.round((values.reduce((total, value, index) => total + (value as number) * metrics[index].maxWeight, 0) / totalWeight) * 1e6) / 1e6
      : null;
    const index = weighted(metrics.map(item => item.index));
    hold.maxWeight = totalWeight;
    hold.maxVolume = metrics.every(item => item.maxVolume !== null) ? Math.round(metrics.reduce((total, item) => total + (item.maxVolume as number), 0) * 1000) / 1000 : null;
    hold.indexPerWeightUnit = index;
    hold.balanceCentroid = weighted(metrics.map(item => item.centroid)) ?? (index !== null && validIndexPerWeightUnitFormula(balanceFormula) ? balanceArmFromIndexPerWeightUnit(index, balanceFormula) : null);
    hold.balanceFrom = metrics.every(item => item.from !== null) ? Math.min(...metrics.map(item => item.from as number)) : null;
    hold.balanceTo = metrics.every(item => item.to !== null) ? Math.max(...metrics.map(item => item.to as number)) : null;
  }

  let rows = [...holds.values()];
  if (!rows.length) errors.push("Add at least one hold or area row below the headings.");
  if (!errors.length) {
    const validated:AircraftD2HoldRow[]=[];
    for(const section of sections){
      const holdType=section==="BULK"?"BLK":"ULD";
      try{validated.push(...validateAircraftD2Section(section,{applicable:true,balanceLimitsRequired:false,rows:rows.filter(row=>row.holdType===holdType)},deckTypes,fuelConfigurations).rows)}
      catch(error){errors.push(error instanceof AircraftD2Invalid?`${section}: ${error.message}`:`Check the imported ${section} Hold values.`)}
    }
    if(!errors.length)rows=validated;
  }
  rows.sort((left, right) => (left.balanceCentroid ?? Number.POSITIVE_INFINITY) - (right.balanceCentroid ?? Number.POSITIVE_INFINITY) || left.name.localeCompare(right.name, undefined, { numeric: true }));
  return { rows, errors, sections: [...sections], source };
}
