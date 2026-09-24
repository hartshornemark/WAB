export const contactFields = [
  { key: "address1", label: "Address line 1", required: true, max: 64 },
  { key: "address2", label: "Address line 2", max: 64 },
  { key: "address3", label: "Address line 3", max: 64 },
  { key: "city", label: "City", required: true, max: 64 },
  { key: "state", label: "State or province", max: 64 },
  { key: "country", label: "Country", required: true, max: 64 },
  { key: "telephone", label: "Telephone", max: 64 },
  { key: "email", label: "Email", max: 64 },
  { key: "teletype", label: "Teletype address", max: 7 },
] as const;
export type ContactKey = typeof contactFields[number]["key"];
export type DetailValues = Record<ContactKey | "weightUnit" | "volumeUnit" | "weightMethod" | "indexDecimalPlaces", string>;
export const emptyDetails: DetailValues = { address1: "", address2: "", address3: "", city: "", state: "", country: "", telephone: "", email: "", teletype: "", weightUnit: "", volumeUnit: "", weightMethod: "", indexDecimalPlaces: "1" };
export interface DetailsSnapshot { canView: boolean; canEdit: boolean; exists: boolean; revision: string; values: DetailValues }
export class DetailsDenied extends Error {}
export class DetailsConflict extends Error {}
export class DetailsInvalid extends Error {
  constructor(public fields: Partial<Record<keyof DetailValues, string>>) { super("Please check the highlighted fields."); }
}
export function a2CarrierContactsStatus(snapshot:Pick<DetailsSnapshot,"values">):"incomplete"|"partial"|"configured"{
  const values=snapshot.values;
  const supplied=contactFields.some(field=>values[field.key].trim()!=="");
  if(!supplied)return"incomplete";
  const valid=contactFields.every(field=>{
    const value=values[field.key].trim();
    if("required" in field&&!value)return false;
    if(value.length>field.max||/[\x00-\x1f\x7f]/.test(value))return false;
    if(field.key==="email"&&value&&!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value))return false;
    if(field.key==="teletype"&&value&&value.length!==7)return false;
    return true;
  });
  return valid?"configured":"partial";
}
export function validateDetails(input: DetailValues): DetailValues {
  const values = { ...emptyDetails };
  const errors: Partial<Record<keyof DetailValues, string>> = {};
  for (const key of Object.keys(values) as (keyof DetailValues)[]) {
    values[key] = typeof input?.[key] === "string" ? input[key].trim() : "";
  }
  for (const field of contactFields) {
    const value = values[field.key];
    if ("required" in field && !value) errors[field.key] = `${field.label} is required.`;
    else if (value.length > field.max) errors[field.key] = `Use no more than ${field.max} characters.`;
    else if (/[\x00-\x1f\x7f]/.test(value)) errors[field.key] = "Enter a single line of text.";
  }
  if (values.email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(values.email)) errors.email = "Enter a valid email address.";
  if (values.teletype && values.teletype.length !== 7) errors.teletype = "Enter exactly 7 characters.";
  if (!["KG", "LB"].includes(values.weightUnit)) errors.weightUnit = "Choose a weight unit.";
  if (!["m3", "ft3"].includes(values.volumeUnit)) errors.volumeUnit = "Choose a volume unit.";
  if (!["BASIC", "DRY_OPERATING"].includes(values.weightMethod)) errors.weightMethod = "Choose a weight method.";
  if (!["1", "2"].includes(values.indexDecimalPlaces)) errors.indexDecimalPlaces = "Choose one or two decimal places.";
  if (Object.keys(errors).length) throw new DetailsInvalid(errors);
  return values;
}
