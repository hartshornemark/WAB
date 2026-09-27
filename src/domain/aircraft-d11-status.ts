import type { DisplayConfigurationStatus } from "@/domain/configuration-status";
import type { AircraftD11Snapshot } from "@/domain/aircraft-d11";

export function d11FloorStatus(snapshot:AircraftD11Snapshot):DisplayConfigurationStatus {
  if (!snapshot.floorActive) return "not_active";
  if (!snapshot.floorLimits.length) return "incomplete";
  const complete = snapshot.floorLimits.filter(row=>typeof row.floorLoadingLimit === "number" && Number.isFinite(row.floorLoadingLimit) && row.floorLoadingLimit > 0).length;
  return complete === snapshot.floorLimits.length ? "configured" : complete ? "partial" : "incomplete";
}

export function aircraftD11Status(snapshot:AircraftD11Snapshot):DisplayConfigurationStatus {
  if (!snapshot.applicabilityReviewed) return "incomplete";
  const floor = d11FloorStatus(snapshot);
  return floor === "not_active" ? "configured" : floor;
}
