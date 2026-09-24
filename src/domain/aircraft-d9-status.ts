import type { DisplayConfigurationStatus } from "@/domain/configuration-status";
import {
  deriveD9ClassSummaries,
  type AircraftD9Snapshot,
  type D9Configuration,
  type D9AreaRow,
  type D9CabinArea,
  type D9Class,
  type D9IndexFormula,
} from "@/domain/aircraft-d9";

const finite = (value:unknown) => typeof value === "number" && Number.isFinite(value);
const optionalBoundaryValid = (value:number|null, centroid:number|null, side:"from"|"to") =>
  value === null || (finite(value) && finite(centroid) && (side === "from" ? value <= centroid! : centroid! <= value));

export const d9AreaComplete = (row:D9AreaRow) =>
  row.classSeats.length === 4 &&
  row.classSeats.every(value => finite(value) && (value ?? -1) >= 0) &&
  Number.isInteger(row.totalSeats) &&
  (row.totalSeats ?? 0) > 0 &&
  row.classSeats.reduce<number>((sum,value) => sum + (value ?? 0), 0) === row.totalSeats &&
  finite(row.centroid) &&
  finite(row.index) &&
  optionalBoundaryValid(row.from, row.centroid, "from") &&
  optionalBoundaryValid(row.to, row.centroid, "to") &&
  (row.from === null || row.to === null || row.from <= row.to);

export function d9ConfigurationStatuses(configuration:D9Configuration, areas:D9CabinArea[], classes:D9Class[], formula?:D9IndexFormula, excludedRows:number[]=[]) {
  const complete = configuration.rows.filter(d9AreaComplete).length;
  const cabin:DisplayConfigurationStatus = !complete ? "incomplete" : complete === areas.length ? "configured" : "partial";
  const summaries = formula && formula.constantC > 0 ? deriveD9ClassSummaries(configuration, areas, classes, formula, excludedRows) : [];
  const cabinTotal = configuration.rows.reduce((sum,row)=>sum+(row.totalSeats??0),0);
  const classTotal = summaries.reduce((sum,row)=>sum+row.totalSeats,0);
  const classInfo:DisplayConfigurationStatus = !summaries.length ? "incomplete" : cabinTotal === classTotal ? "configured" : "partial";
  return {
    cabin,
    classInfo,
    page:cabin === "configured" && classInfo === "configured" ? "configured" : cabin === "incomplete" && classInfo === "incomplete" ? "incomplete" : "partial",
  } as const;
}

export function aircraftD9Status(snapshot:AircraftD9Snapshot, formula?:D9IndexFormula):DisplayConfigurationStatus {
  if (!snapshot.configurations.length) return "incomplete";
  const states = snapshot.configurations.map(configuration=>d9ConfigurationStatuses(configuration,snapshot.cabinAreas,snapshot.classes,formula,snapshot.excludedRows).page);
  return states.every(state=>state === "configured") ? "configured" : states.every(state=>state === "incomplete") ? "incomplete" : "partial";
}
