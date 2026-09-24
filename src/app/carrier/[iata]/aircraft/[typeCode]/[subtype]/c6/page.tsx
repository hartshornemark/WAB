import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { aircraftC1Services, services } from "@/composition/services";
import { AuthenticationRequired, CarrierUnavailable } from "@/domain/models";
import { WorkspaceShell } from "@/components/workspace-shell";
import { AircraftContextHeading } from "@/components/aircraft-context-heading";
import { SectionHeader } from "@/components/section-header";

export default async function AircraftC6Page({ params }: { params: Promise<{ iata: string; typeCode: string; subtype: string }> }) {
  const { iata, typeCode, subtype } = await params;
  const result = await (await services()).selectCarrier(iata).catch(error => {
    if (error instanceof AuthenticationRequired) redirect("/login");
    if (error instanceof CarrierUnavailable) notFound();
    throw error;
  });
  const c1 = await (await aircraftC1Services()).get(iata, typeCode, subtype);
  if (!c1.typeCode) notFound();
  const aircraftPath = `/carrier/${encodeURIComponent(iata)}/aircraft/${encodeURIComponent(typeCode)}/${encodeURIComponent(subtype)}`;

  return <WorkspaceShell user={result.user}>
    <Link href={`/carrier/${encodeURIComponent(iata)}/aircraft`} className="back">← Change aircraft</Link>
    <p className="eyebrow">CARRIER WORKSPACE / {result.carrier.iata} / {c1.typeCode}-{c1.subtype}</p>
    <AircraftContextHeading iata={iata} logoUrl={result.carrier.logoUrl} carrierName={result.carrier.name} aircraft={c1}/>
    <section className="aircraft-c5" aria-labelledby="aircraft-c6-heading">
      <SectionHeader id="aircraft-c6-heading" title="5. CURTAILMENTS" reference="(AHM565 Sheet C6)"/>
      <p className="c5-intro">This section is reserved for Curtailments used when a manufacturer&apos;s Balance Envelope is supplied. It is currently skipped in the aircraft workflow.</p>
      <div className="c5-status-card">
        <div><h3>C6 is Not Currently Active</h3><p>Future records will accommodate the Curtailment Type or Name, applicability to Taxi, Take-Off, Landing, Zero Fuel and Inflight limits, Forward and Aft % MAC or Index values, Sum of Square selection, Applicability Rule and Remarks.</p></div>
        <span className="c5-status warning">SKIPPED</span>
      </div>
    </section>
    <nav className="section-navigation" aria-label="Aircraft setup sections">
      <Link className="section-link secondary" href={`${aircraftPath}/c5`}>← C5.1. CG LIMITS</Link>
      <Link className="section-link" href={`${aircraftPath}/c7`}>NEXT: C7. IDEAL TRIM →</Link>
    </nav>
  </WorkspaceShell>;
}
