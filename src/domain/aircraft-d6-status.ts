import type { DisplayConfigurationStatus } from "@/domain/configuration-status";
import type {
  AircraftD6Snapshot,
  GalleyLocation,
  WaterLocation,
} from "@/domain/aircraft-d6";

const finite = (value: unknown) => typeof value === "number" && Number.isFinite(value);
export const waterLocationComplete = (row: WaterLocation) =>
  !!row.id && !!row.name && finite(row.maxWeight) && (row.maxWeight ?? 0) > 0 &&
  finite(row.centroid) && finite(row.index);
export const galleyLocationComplete = (row: GalleyLocation) =>
  !!row.id && !!row.description && finite(row.maxWeight) && (row.maxWeight ?? 0) > 0 &&
  finite(row.centroid) && finite(row.index);

export function d6SectionStatus<T>(
  applicable: boolean | null,
  rows: T[],
  complete: (row: T) => boolean,
): DisplayConfigurationStatus {
  if (applicable === null) return "incomplete";
  if (applicable === false) return "not_active";
  if (!rows.length) return "incomplete";
  const completed = rows.filter(complete).length;
  return completed === rows.length ? "configured" : completed ? "partial" : "incomplete";
}

export function aircraftD6Statuses(snapshot: AircraftD6Snapshot) {
  return {
    waterLocations: d6SectionStatus(
      snapshot.waterApplicable,
      snapshot.waterLocations,
      waterLocationComplete,
    ),
    galleyLocations: d6SectionStatus(
      snapshot.galleyApplicable,
      snapshot.galleyLocations,
      galleyLocationComplete,
    ),
  };
}

export function aircraftD6Status(snapshot: AircraftD6Snapshot): DisplayConfigurationStatus {
  const values = Object.values(aircraftD6Statuses(snapshot));
  const normalised = values.map((status) => status === "not_active" ? "configured" : status);
  if (normalised.every((status) => status === "configured")) return "configured";
  if (normalised.every((status) => status === "incomplete")) return "incomplete";
  return "partial";
}
