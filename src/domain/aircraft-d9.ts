import {cabinRowNumbers} from "./cabin-row-sequence";
import {physicalSeatGrouping} from "./aircraft-d8";
import {
  balanceArmFromIndexPerWeightUnit,
  validIndexPerWeightUnitFormula,
  type IndexPerWeightUnitFormula,
} from "@/domain/index-per-weight-unit";

export type D9CabinArea = { id:string; rowFrom:number; rowTo:number; rowSequence?:number[]|null; centroid:number; from:number; to:number; index:number|null };
export type D9Class = { code:string|null; name:string|null; slot:1|2|3|4 };
export type D9AreaRow = {
  areaId:string;
  blockedRows?:number[];
  classSeats:[number|null,number|null,number|null,number|null];
  totalSeats:number|null;
  centroid:number|null;
  from:number|null;
  to:number|null;
  index:number|null;
};
export type D9Configuration = { code:string; description:string; rows:D9AreaRow[] };
export type D9PhysicalRow = {areaId:string;rowNumber:number;maximumSeats:number|null;grouping:string|null};
export type D9SeatDraftValue = number|string|null;
export type AircraftD9Snapshot = {
  seatRows?:D9PhysicalRow[];
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

/**
 * Keep a cabin-area allocation complete while the user works from one class
 * to the next. The next defined class receives the remaining usable seats;
 * later classes are reset to zero until the user works further along the row.
 */
export function spillD9ClassSeats(
  current:readonly D9SeatDraftValue[],
  editedIndex:number,
  value:D9SeatDraftValue,
  activeSlots:readonly D9Class["slot"][],
  availableSeats:number|null,
):[D9SeatDraftValue,D9SeatDraftValue,D9SeatDraftValue,D9SeatDraftValue] {
  const result=Array.from({length:4},(_,index)=>current[index]??null) as [D9SeatDraftValue,D9SeatDraftValue,D9SeatDraftValue,D9SeatDraftValue];
  result[editedIndex]=value;
  const indexes=[...activeSlots].sort((a,b)=>a-b).map(slot=>slot-1),position=indexes.indexOf(editedIndex);
  if(position<0||availableSeats===null||!Number.isInteger(availableSeats)||availableSeats<0)return result;
  if(value===""||value===null){for(const index of indexes.slice(position+1))result[index]=null;return result;}
  const entered=Number(value);
  if(!Number.isInteger(entered)||entered<0)return result;
  const next=indexes[position+1];
  if(next===undefined)return result;
  const allocated=indexes.slice(0,position+1).reduce((sum,index)=>{
    const candidate=Number(result[index]);
    return sum+(result[index]!==""&&result[index]!==null&&Number.isInteger(candidate)&&candidate>=0?candidate:0);
  },0);
  result[next]=Math.max(0,availableSeats-allocated);
  for(const index of indexes.slice(position+2))result[index]=0;
  return result;
}

export function validateD9Configuration(value:unknown, areas:D9CabinArea[], classes:D9Class[], formula?:IndexPerWeightUnitFormula|null, seatRows?:D9PhysicalRow[]) {
  const configuration = value as Partial<D9Configuration>;
  const code = String(configuration.code ?? "").trim().toUpperCase();
  const activeSlots = new Set(classes.filter(carrierClass => carrierClass.code && carrierClass.name).map(carrierClass => carrierClass.slot));
  if (!/^[A-Z]$/.test(code)) throw new AircraftD9Invalid("Configuration Code must be one letter (A–Z).");
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
    const blockedRows=row.blockedRows??[];
    if(!Array.isArray(blockedRows)||blockedRows.some(n=>!Number.isInteger(n)||!cabinRowNumbers(area).includes(n))||new Set(blockedRows).size!==blockedRows.length)throw new AircraftD9Invalid(`Check blocked rows for Cabin Area ${area.id}.`);
    const result={ areaId:area.id, classSeats, totalSeats, centroid, from, to, index, blockedRows:[...blockedRows].sort((a,b)=>a-b) };
    if(seatRows){const problem=d9SeatPlanProblem(result,seatRows);if(problem)throw new AircraftD9Invalid(problem);}
    return result;
  });

  const suggestedDescription = suggestD9Description(rows, classes);
  const description = String(configuration.description ?? "").trim() || suggestedDescription;
  if (!description || description.length > 20) throw new AircraftD9Invalid("Enter a Configuration Description of up to 20 characters.");
  return { code, description, rows };
}

export function deriveD9ClassSummaries(configuration:D9Configuration, areas:D9CabinArea[], classes:D9Class[], formula:D9IndexFormula={referenceArm:0,constantC:1}, excludedRows:number[]=[]):D9ClassSummary[] {
  const first=(area:D9CabinArea)=>cabinRowNumbers(area,excludedRows)[0]??area.rowFrom;
  const last=(area:D9CabinArea)=>cabinRowNumbers(area,excludedRows).at(-1)??area.rowTo;
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
        firstRow:first([...used].sort((a,b)=>a.area!.centroid-b.area!.centroid)[0].area!),
        lastRow:last([...used].sort((a,b)=>a.area!.centroid-b.area!.centroid).at(-1)!.area!),
        totalSeats,
        centroid,
        from,
        to,
        index:(centroid-formula.referenceArm)/formula.constantC,
      }];
    });
}

export function d9SeatPlanProblem(row:Pick<D9AreaRow,"areaId"|"totalSeats"|"blockedRows">,physical:D9PhysicalRow[]):string|null {
 const rows=physical.filter(r=>r.areaId===row.areaId),blocked=row.blockedRows??[];
 for(const n of blocked){const r=rows.find(r=>r.rowNumber===n);if(!r||!/^3(-3){0,3}$/.test(r.grouping??""))return `Row ${n}: blocked centres require three-seat groups saved on D8.`;}
 // D9 may be entered before D8; compare totals once its physical rows are available.
 if(!rows.length||rows.some(r=>r.maximumSeats==null))return blocked.length?"Complete D8 before blocking seats.":null;
 const total=d9UsableSeatTotal(row.areaId,blocked,physical)!;
 return total!==row.totalSeats?`Cabin Area ${row.areaId}: the seat map has ${total} usable seats, but the class allocations total ${row.totalSeats}. Update the class seats or blocked rows.`:null;
}

export function d9UsableSeatTotal(areaId:string,blockedRows:readonly number[],physical:D9PhysicalRow[]):number|null {
 const rows=physical.filter(row=>row.areaId===areaId);
 if(!rows.length||rows.some(row=>row.maximumSeats===null))return null;
 return rows.reduce((sum,row)=>sum+row.maximumSeats!-(blockedRows.includes(row.rowNumber)&&row.grouping?physicalSeatGrouping(row.grouping).split("-").length:0),0);
}
