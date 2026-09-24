export const passengerFields = ["adult","male","female","child","infant","handBaggage"] as const;
export type PassengerField = typeof passengerFields[number];
export type PassengerValues = Record<PassengerField, number | null> & { includesHandBaggage: boolean; remarks: string };
export type PassengerDraft = Record<PassengerField, string> & { includesHandBaggage: boolean; remarks: string };
export type FlightVariation = { code: string; description: string };
export type PassengerRow = PassengerValues & { id: string | null; classCode: string | null; variation: string | null };
export type PassengerRowDraft = PassengerDraft & Pick<PassengerRow,"id"|"classCode"|"variation">;
export type PassengerSection = "default" | "classes" | "variations";
export type PassengerSnapshot = {
  canView: boolean; canEdit: boolean; revision: string; unit: "KG" | "LB" | null;
  defaultWeights: PassengerValues | null; rows: PassengerRow[];
  variations: FlightVariation[]; masterVariations: FlightVariation[]; classes: FlightVariation[];
  variationsReviewed: boolean; classWeightsReviewed: boolean;
};
export class PassengerInvalid extends Error {}
export class PassengerDenied extends Error {}
export class PassengerConflict extends Error {}
export function passengerDraft(values?: PassengerValues | null): PassengerDraft {
  return { adult: values?.adult?.toString() ?? "", male: values?.male?.toString() ?? "", female: values?.female?.toString() ?? "", child: values?.child?.toString() ?? "", infant: values?.infant?.toString() ?? "", handBaggage: values?.handBaggage?.toString() ?? "", includesHandBaggage: values?.includesHandBaggage ?? true, remarks: values?.remarks ?? "" };
}
function object(value: unknown): Record<string,unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new PassengerInvalid("Check the entries.");
  return value as Record<string,unknown>;
}
export function validatePassengerValues(input: unknown): PassengerValues {
  const v = object(input);
  if (typeof v.includesHandBaggage !== "boolean" || typeof v.remarks !== "string" || v.remarks.length > 2000) throw new PassengerInvalid("Check the baggage selection and keep remarks within 2,000 characters.");
  const result = { includesHandBaggage: v.includesHandBaggage, remarks: v.remarks } as PassengerValues;
  for (const key of passengerFields) {
    const raw = v[key];
    const optional = key === "adult" || (key === "handBaggage" && v.includesHandBaggage);
    if ((raw === "" || raw === null) && optional) { result[key] = null; continue; }
    if (typeof raw !== "string" && typeof raw !== "number") throw new PassengerInvalid("Enter all required weights.");
    const n = Number(raw);
    if (!/^[0-9]+$/.test(String(raw)) || !Number.isSafeInteger(n) || n > 2147483647 || n < (key === "infant" || key === "handBaggage" ? 0 : 1)) throw new PassengerInvalid("Use positive whole-number passenger weights. Infant and hand-baggage weights may be zero. A separate hand-baggage weight is required when it is not included.");
    result[key] = n;
  }
  return result;
}
export function validateVariations(input: unknown): FlightVariation[] {
  if (!Array.isArray(input) || input.length > 100) throw new PassengerInvalid("Keep no more than 100 flight variations.");
  const codes = new Set<string>(), labels = new Set<string>();
  return input.map(value => {
    const v = object(value);
    if (typeof v.code !== "string" || typeof v.description !== "string") throw new PassengerInvalid("Enter a code and description.");
    const code = v.code.trim().toUpperCase(), description = v.description.trim();
    if (!/^[A-Z0-9]{3}$/.test(code) || !description || description.length > 64 || /[\u0000-\u001f\u007f]/.test(description)) throw new PassengerInvalid("Variation codes need three letters or numbers; descriptions need 1–64 characters.");
    if (codes.has(code) || labels.has(description.toLowerCase())) throw new PassengerInvalid("Each variation code and description must be unique.");
    codes.add(code); labels.add(description.toLowerCase());
    return { code, description };
  });
}
export function validatePassengerRows(input: unknown, current: PassengerSnapshot): PassengerRow[] {
  if (!Array.isArray(input) || input.length > 200) throw new PassengerInvalid("Keep no more than 200 class weight sets.");
  const pairs = new Set<string>(), ids = new Set<string>();
  return input.map(value => {
    const row = object(value);
    if (row.classCode !== null && (typeof row.classCode !== "string" || !current.classes.some(c => c.code === row.classCode))) throw new PassengerInvalid("Choose All Classes or a class saved on B1.");
    if (row.variation !== null && (typeof row.variation !== "string" || !current.variations.some(v => v.code === row.variation))) throw new PassengerInvalid("Choose Standard/Default or an adopted flight variation.");
    if (row.classCode === null && row.variation === null) throw new PassengerInvalid("Choose a Flight Variation when the table applies to All Classes. The Standard table already covers all other flights.");
    if (row.id !== null && (typeof row.id !== "string" || !current.rows.some(r => r.id === row.id) || ids.has(row.id))) throw new PassengerInvalid("This weight set changed. Reload before editing.");
    if (typeof row.id === "string") ids.add(row.id);
    const pair = (row.classCode ?? "") + ":" + (row.variation ?? "");
    if (pairs.has(pair)) throw new PassengerInvalid("Only one weight set is allowed for each class and flight variation.");
    pairs.add(pair);
    return { ...validatePassengerValues(row), id: row.id as string | null, classCode: row.classCode as string | null, variation: row.variation as string | null };
  });
}
