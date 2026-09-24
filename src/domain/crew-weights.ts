export const crewWeightFields = [
  "flightDeckMale", "flightDeckFemale", "cabinMale", "cabinFemale",
  "flightDeckHand", "cabinHand", "flightDeckLong", "flightDeckShort", "flightDeckOther",
  "cabinLong", "cabinShort", "cabinOther",
] as const;
export type CrewWeightKey = typeof crewWeightFields[number];
export const holdCategories = [
  { key: "allFlights", label: "All Flights", flightDeck: "flightDeckOther", cabin: "cabinOther" },
  { key: "longhaul", label: "Longhaul", flightDeck: "flightDeckLong", cabin: "cabinLong" },
  { key: "shorthaul", label: "Shorthaul", flightDeck: "flightDeckShort", cabin: "cabinShort" },
] as const;
export type HoldSelection = Record<typeof holdCategories[number]["key"], boolean>;
export function selectHoldCategory<T extends HoldSelection>(current: T, key: keyof HoldSelection, checked: boolean): T {
  return { ...current, [key]: checked, ...(checked ? key === "allFlights" ? { longhaul: false, shorthaul: false } : { allFlights: false } : {}) };
}
export type CrewValues = Record<CrewWeightKey, number | null> & HoldSelection & { includesHandBaggage: boolean };
export type CrewDraft = Record<CrewWeightKey, string> & HoldSelection & { includesHandBaggage: boolean };
export type CrewSnapshot = { canView: boolean; canEdit: boolean; exists: boolean; revision: string; unit: "KG" | "LB" | null; values: CrewValues };
export class CrewInvalid extends Error {}
export class CrewDenied extends Error {}
export class CrewConflict extends Error {}
export function crewDraft(values: CrewValues): CrewDraft {
  return { ...Object.fromEntries(crewWeightFields.map(key => [key, values[key] === null ? "" : String(values[key])])), includesHandBaggage: values.includesHandBaggage, allFlights: values.allFlights, longhaul: values.longhaul, shorthaul: values.shorthaul } as CrewDraft;
}
export function validateCrewWeights(input: unknown): CrewValues {
  if (!input || typeof input !== "object") throw new CrewInvalid("Check the crew weights.");
  const row = input as Record<string, unknown>;
  if (typeof row.includesHandBaggage !== "boolean") throw new CrewInvalid("Choose whether crew weights include hand baggage.");
  for (const { key } of holdCategories) {
    if (typeof row[key] !== "boolean") throw new CrewInvalid("Select which flights the Crew Hold Baggage weights apply to.");
  }
  if (!row.allFlights && !row.longhaul && !row.shorthaul) throw new CrewInvalid("Select All Flights, Longhaul and/or Shorthaul for Crew Hold Baggage.");
  if (row.allFlights && (row.longhaul || row.shorthaul)) throw new CrewInvalid("All Flights cannot be selected with Longhaul or Shorthaul.");
  const values = { includesHandBaggage: row.includesHandBaggage, allFlights: row.allFlights, longhaul: row.longhaul, shorthaul: row.shorthaul } as CrewValues;
  for (const key of crewWeightFields) {
    const raw = row[key];
    const text = typeof raw === "string" ? raw.trim() : raw === null ? "" : typeof raw === "number" ? String(raw) : undefined;
    const crew = ["flightDeckMale", "flightDeckFemale", "cabinMale", "cabinFemale"].includes(key);
    const required = holdCategories.some(category => row[category.key] && (category.flightDeck === key || category.cabin === key)) || crew || (!row.includesHandBaggage && ["flightDeckHand", "cabinHand"].includes(key));
    if (text === "" && !required) { values[key] = null; continue; }
    if (text === undefined || !/^[0-9]+$/.test(text)) throw new CrewInvalid(required ? "Enter all crew weights, both weights for each selected flight category and, when not included, both hand-baggage weights as whole numbers." : "Use whole numbers for baggage weights, or leave them blank when not specified.");
    const value = Number(text);
    if (!Number.isSafeInteger(value) || value > 2147483647 || value < (crew ? 1 : 0)) throw new CrewInvalid("Crew weights must be greater than zero; baggage weights must be zero or greater. Use whole numbers within the supported range.");
    values[key] = value;
  }
  return values;
}
