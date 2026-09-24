import type{AircraftC2Snapshot}from"@/domain/aircraft-c2";
import type{ConfigurationStatus}from"@/domain/configuration-status";

export function a5AutomaticDocumentsStatus(snapshot:Pick<AircraftC2Snapshot,"documents">):ConfigurationStatus{
  return snapshot.documents.some(document=>document.required)?"configured":"incomplete";
}
