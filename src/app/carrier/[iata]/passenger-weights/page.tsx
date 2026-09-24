import Link from "next/link";
import { redirect, notFound } from "next/navigation";
import { services, passengerServices, aircraftC1Services } from "@/composition/services";
import { carrierCarriesPassengers } from "@/domain/aircraft-c1";
import { AuthenticationRequired, CarrierUnavailable } from "@/domain/models";
import { WorkspaceShell } from "@/components/workspace-shell";
import { CarrierLogo } from "@/components/carrier-logo";
import { PassengerWeights } from "@/components/passenger-weights";
export default async function PassengerWeightsPage({ params }: { params: Promise<{ iata: string }> }) {
  const { iata } = await params;
  const result = await (await services()).selectCarrier(iata).catch(error => {
    if (error instanceof AuthenticationRequired) redirect("/login");
    if (error instanceof CarrierUnavailable) notFound();
    throw error;
  });
  const [snapshot,aircraft] = await Promise.all([(await passengerServices()).get(iata),(await aircraftC1Services()).list(iata)]);
  return <WorkspaceShell user={result.user}>
    <Link href="/carriers" className="back">← Change carrier</Link>
    <p className="eyebrow">CARRIER WORKSPACE / {result.carrier.iata}</p>
    <div className="crew-carrier-heading"><CarrierLogo iata={iata} logoUrl={result.carrier.logoUrl} /><h1>{result.carrier.name}</h1></div>
    <PassengerWeights key={iata} iata={iata} initial={snapshot} passengerOperations={carrierCarriesPassengers(aircraft.rows)} />
    <nav className="section-navigation" aria-label="Carrier setup sections"><Link className="section-link secondary" href={`/carrier/${encodeURIComponent(iata)}/crew-weights`}>← B2. CREW</Link><Link className="section-link" href={`/carrier/${encodeURIComponent(iata)}/baggage-weights`}>NEXT: B4. BAGGAGE →</Link></nav>
  </WorkspaceShell>;
}
