import {
  balanceArmFromIndexPerWeightUnit,
  validIndexPerWeightUnitFormula,
  type IndexPerWeightUnitFormula,
} from "@/domain/index-per-weight-unit";

export type D9CabinArea = { id:string; rowFrom:number; rowTo:number; centroid:number; from:number; to:number; index:number|null };
export type D9Class = { code:string|null; name:string|null; slot:1|2|3|4 };
export type D9AreaRow = {
  areaId:string;
  classSeats:[number|null,number|null,number|null,number|null];
  totalSeats:number|null;
  centroid:number|null;
  from:number|null;
  to:number|null;
  index:number|null;
};
export type D9Configuration = { code:string; description:string; rows:D9AreaRow[] };
export type AircraftD9Snapshot = {
  canView:boolean;
  canEdit:boolean;
  revision:string;
  typeCode:string;
  subtype:string;
  excludedRows:number[];
  cabinAreas:D9CabinArea[];
  classes:D9Class[];
  configurations:D9Configuration[];
  balanceFormula?:IndexPerWeightUnitFormula|null;
};
export type D9IndexFormula = IndexPerWeightUnitFormula;
export type D9ClassSummary = { code:string; name:string; firstRow:number; lastRow:number; totalSeats:number; centroid:number; from:number; to:number; index:number };
export class AircraftD9Invalid extends Error {}
export class AircraftD9Denied extends Error {}
export class AircraftD9Conflict extends Error {}

const finite = (value:unknown, label:string, positive=false, integer=false) => {
  const number = typeof value === "number" ? value : Number(value);
  if (value === null || value === "" || typeof value === "boolean" || !Number.isFinite(number) || (positive && number <= 0) || (integer && !Number.isInteger(number))) {
    throw new AircraftD9Invalid(`Enter a valid ${label}.`);
  }
  return number;
};
const optionalFinite = (value:unknown, label:string) => value === null || value === "" || value === undefined ? null : finite(value, label);

export function buildD9Rows(areas:D9CabinArea[], saved:D9AreaRow[]) {
  const savedByArea = new Map(saved.map(row => [row.areaId, row]));
  return areas.map(area => savedByArea.get(area.id) ?? {
    areaId: area.id,
    classSeats: [null, null, null, null] as D9AreaRow["classSeats"],
    totalSeats: null,
    centroid: area.centroid,
    from: area.from,
    to: area.to,
    index: area.index,
  });
}

export function suggestD9Description(rows:{classSeats:readonly unknown[]}[], classes:D9Class[]) {
  return classes
    .filter((carrierClass): carrierClass is D9Class & { code:string; name:string } => !!carrierClass.code && !!carrierClass.name)
    .sort((a,b) => a.slot - b.slot)
    .map(carrierClass => {
      const seats = rows.reduce((sum,row) => sum + (Number(row.classSeats[carrierClass.slot - 1]) || 0), 0);
      return seats > 0 ? `${carrierClass.code}${seats}` : "";
    })
    .join("");
}

export function validateD9Configuration(value:unknown, areas:D9CabinArea[], classes:D9Class[], formula?:IndexPerWeightUnitFormula|null) {
  const configuration = value as Partial<D9Configuration>;
  const code = String(configuration.code ?? "").trim().toUpperCase();
  const activeSlots = new Set(classes.filter(carrierClass => carrierClass.code && carrierClass.name).map(carrierClass => carrierClass.slot));
  if (!/^[A-Z0-9]$/.test(code)) throw new AircraftD9Invalid("Configuration Code must be one letter or number.");
  if (!activeSlots.size) throw new AircraftD9Invalid("Configure at least one carrier class before D9.");
  if (!validIndexPerWeightUnitFormula(formula)) throw new AircraftD9Invalid("Configure C4 before calculating Balance Arm Centroid.");
  if (!Array.isArray(configuration.rows)) throw new AircraftD9Invalid("Check the Cabin Area rows.");

  const rowsByArea = new Map(configuration.rows.map(row => [row.areaId, row]));
  const rows = areas.map(area => {
    const row = rowsByArea.get(area.id);
    if (!row) throw new AircraftD9Invalid(`Complete Cabin Area ${area.id}.`);
    const classSeats = Array.from({length:4}, (_,index) => activeSlots.has((index + 1) as D9Class["slot"])
      ? finite(row.classSeats[index], `Class ${index + 1} Seats for ${area.id}`, false, true)
      : 0) as [number,number,number,number];
    if (classSeats.some(seats => seats < 0)) throw new AircraftD9Invalid(`Class seats for ${area.id} cannot be negative.`);
    const totalSeats = classSeats.reduce((sum,seats) => sum + seats, 0);
    if (totalSeats <= 0) throw new AircraftD9Invalid(`Enter at least one seat for Cabin Area ${area.id}.`);
    const index = finite(row.index, `Index per Weight Unit for ${area.id}`);
    const centroid = balanceArmFromIndexPerWeightUnit(index, formula);
    const from = optionalFinite(row.from, `Balance Arm From for ${area.id}`);
    const to = optionalFinite(row.to, `Balance Arm To for ${area.id}`);
    if (from !== null && from > centroid) throw new AircraftD9Invalid(`Balance Arm From for ${area.id} cannot be greater than the calculated Centroid.`);
    if (to !== null && centroid > to) throw new AircraftD9Invalid(`Balance Arm To for ${area.id} cannot be less than the calculated Centroid.`);
    if (from !== null && to !== null && from > to) throw new AircraftD9Invalid(`Balance Arm From for ${area.id} cannot be greater than Balance Arm To.`);
    return { areaId:area.id, classSeats, totalSeats, centroid, from, to, index };
  });

  const suggestedDescription = suggestD9Description(rows, classes);
  const description = String(configuration.description ?? "").trim() || suggestedDescription;
  if (!description || description.length > 20) throw new AircraftD9Invalid("Enter a Configuration Description of up to 20 characters.");
  return { code, description, rows };
}

export function deriveD9ClassSummaries(configuration:D9Configuration, areas:D9CabinArea[], classes:D9Class[], formula:D9IndexFormula={referenceArm:0,constantC:1}, excludedRows:number[]=[]):D9ClassSummary[] {
  const excluded = new Set(excludedRows);
  const first = (area:D9CabinArea) => Array.from({length:area.rowTo-area.rowFrom+1},(_,index)=>area.rowFrom+index).find(row=>!excluded.has(row)) ?? area.rowFrom;
  const last = (area:D9CabinArea) => Array.from({length:area.rowTo-area.rowFrom+1},(_,index)=>area.rowTo-index).find(row=>!excluded.has(row)) ?? area.rowTo;
  return classes
    .filter((carrierClass):carrierClass is D9Class & {code:string;name:string} => !!carrierClass.code && !!carrierClass.name)
    .flatMap(carrierClass => {
      const used = configuration.rows
        .map(row => ({ row, area:areas.find(area=>area.id===row.areaId), seats:row.classSeats[carrierClass.slot-1] ?? 0 }))
        .filter(value => value.area && value.seats > 0);
      if (!used.length) return [];
      const totalSeats = used.reduce((sum,value)=>sum+value.seats,0);
      const from = Math.min(...used.map(value=>value.row.from ?? value.row.centroid ?? 0));
      const to = Math.max(...used.map(value=>value.row.to ?? value.row.centroid ?? 0));
      const centroid = (from+to)/2;
      return [{
        code:carrierClass.code,
        name:carrierClass.name,
        firstRow:Math.min(...used.map(value=>first(value.area!))),
        lastRow:Math.max(...used.map(value=>last(value.area!))),
        totalSeats,
        centroid,
        from,
        to,
        index:(centroid-formula.referenceArm)/formula.constantC,
      }];
    });
}
