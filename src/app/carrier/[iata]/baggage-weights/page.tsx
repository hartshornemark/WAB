import Link from "next/link";
import { redirect, notFound } from "next/navigation";
import { services, baggageServices } from "@/composition/services";
import { AuthenticationRequired, CarrierUnavailable } from "@/domain/models";
import { WorkspaceShell } from "@/components/workspace-shell";
import { CarrierLogo } from "@/components/carrier-logo";
import { BaggageWeights } from "@/components/baggage-weights";
export default async function BaggageWeightsPage({ params }: { params: Promise<{ iata: string }> }) {
  const { iata } = await params;
  const result = await (await services()).selectCarrier(iata).catch(error => {
    if (error instanceof AuthenticationRequired) redirect("/login");
    if (error instanceof CarrierUnavailable) notFound();
    throw error;
  });
  const snapshot = await (await baggageServices()).get(iata);
  return <WorkspaceShell user={result.user}>
    <Link href="/carriers" className="back">← Change carrier</Link>
    <p className="eyebrow">CARRIER WORKSPACE / {result.carrier.iata}</p>
    <div className="crew-carrier-heading"><CarrierLogo iata={iata} logoUrl={result.carrier.logoUrl} /><h1>{result.carrier.name}</h1></div>
    <BaggageWeights key={iata} iata={iata} initial={snapshot} />
    <nav className="section-navigation" aria-label="Carrier setup sections"><Link className="section-link secondary" href={`/carrier/${encodeURIComponent(iata)}/passenger-weights`}>← B3. PASSENGERS</Link><Link className="section-link" href={`/carrier/${encodeURIComponent(iata)}/uld-specifications`}>NEXT: B5. ULD SPEC →</Link></nav>
  </WorkspaceShell>;
}
