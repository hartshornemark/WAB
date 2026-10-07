export type CsvAircraftIdentity = { typeCode: string; subtype: string };

export const csvAircraftIdentityHeaders = ["Aircraft Type IATA", "Series/Sub-Type"] as const;

export const normaliseCsvAircraftIdentity = (value: string | undefined) =>
  String(value ?? "").trim().toUpperCase().replace(/[^A-Z0-9-]/g, "");

export function csvAircraftIdentityError(
  source: CsvAircraftIdentity,
  expected: CsvAircraftIdentity,
  line?: number,
) {
  const prefix = line ? `Line ${line}: ` : "";
  if (!source.typeCode || !source.subtype) {
    return `${prefix}Aircraft Type IATA and Series/Sub-Type are required. Download a new template for this aircraft.`;
  }
  if (source.typeCode !== normaliseCsvAircraftIdentity(expected.typeCode)
    || source.subtype !== normaliseCsvAircraftIdentity(expected.subtype)) {
    return `${prefix}CSV aircraft ${source.typeCode}-${source.subtype} does not match the open aircraft ${normaliseCsvAircraftIdentity(expected.typeCode)}-${normaliseCsvAircraftIdentity(expected.subtype)}.`;
  }
  return null;
}

export const csvAircraftLabel = (identity: CsvAircraftIdentity | null) =>
  identity ? `${identity.typeCode}-${identity.subtype}` : "—";
