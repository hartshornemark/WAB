import { CarrierLogo } from "@/components/carrier-logo";
import type { AircraftC1Snapshot } from "@/domain/aircraft-c1";

type AircraftContextHeadingProps = {
  iata: string;
  logoUrl?: string | null;
  carrierName: string;
  aircraft: AircraftC1Snapshot;
};

export function AircraftContextHeading({ iata, logoUrl, carrierName, aircraft }: AircraftContextHeadingProps) {
  const aircraftName = aircraft.aircraftName || aircraft.identityName;
  return <div className="aircraft-context-heading">
    <div className="aircraft-context-carrier">
      <CarrierLogo iata={iata} logoUrl={logoUrl}/>
      <div><h1>{carrierName}</h1><p>{aircraftName}</p></div>
    </div>
    <aside className="aircraft-identity-summary" aria-label="Aircraft Identity">
      <span>AIRCRAFT IDENTITY</span>
      <h2>{aircraftName}</h2>
      <p>{aircraft.manufacturerName || "Manufacturer Not Yet Assigned"} · Aircraft Type {aircraft.typeCode} · Series/Sub-Type {aircraft.subtype}</p>
    </aside>
  </div>;
}
