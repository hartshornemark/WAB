import { CarrierLogo } from "@/components/carrier-logo";
import Link from "next/link";
import { redirect } from "next/navigation";
import { services,carrierAdministrationServices } from "@/composition/services";
import { AuthenticationRequired } from "@/domain/models";
import { WorkspaceShell } from "@/components/workspace-shell";
export default async function Carriers() {
  const result = await (await services()).listCarriers().catch(error => {
    if (error instanceof AuthenticationRequired) redirect("/login");
    throw error;
  });
  const administration=await(await carrierAdministrationServices()).access();
  return <WorkspaceShell user={result.user}><p className="eyebrow">YOUR WORKSPACE</p><div className="carrier-selection-heading"><div><h1>Select a carrier</h1><p className="muted">Choose the airline you want to work with.</p></div>{administration.canCreate&&<Link className="button-link" href="/carriers/new">ADD NEW CARRIER</Link>}</div><div className="section-heading"><h2>Authorised carriers</h2><span className="badge">{result.carriers.length} available</span></div>
    {result.carriers.length ? <div className="carrier-grid">{result.carriers.map(carrier => <Link prefetch={false} className="carrier-card" key={carrier.iata} href={`/carrier/${encodeURIComponent(carrier.iata)}/dashboard`}><CarrierLogo iata={carrier.iata} logoUrl={carrier.logoUrl} /><div><h3>{carrier.name}</h3><p>{carrier.iata} · Open carrier workspace</p></div><span className="arrow" aria-hidden="true">↗</span></Link>)}</div> : <section className="empty"><h2>No carriers available</h2><p>Your account is signed in, but no carriers are available to you. Contact your organisation administrator to request access.</p></section>}
  </WorkspaceShell>;
}
