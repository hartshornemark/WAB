import { CarrierLogo } from "@/components/carrier-logo";
import Link from "next/link";
import { redirect } from "next/navigation";
import { services,carrierAdministrationServices,aircraftC1Services } from "@/composition/services";
import { AuthenticationRequired } from "@/domain/models";
import { WorkspaceShell } from "@/components/workspace-shell";

const workRoutes={schedules:"flight-schedules","load-control":"load-control",ahm:"dashboard"} as const;
const labels={schedules:"Schedule Creation / Amendment",loadControl:"Load Control",ahm:"AHM560 / 565 Database"} as const;

export default async function Carriers({searchParams}:{searchParams:Promise<{work?:string}>}) {
  const work=(await searchParams).work;
  if(work==="load-control")redirect("/load-control");
  const route=workRoutes[work as keyof typeof workRoutes];
  const label=work==="schedules"?labels.schedules:work==="ahm"?labels.ahm:null;
  const result=await(await services()).listCarriers().catch(error=>{if(error instanceof AuthenticationRequired)redirect("/login");throw error});
  const carriers=work==="schedules"
    ?(await Promise.all(result.carriers.map(async carrier=>({carrier,aircraft:await(await aircraftC1Services()).list(carrier.iata).catch(()=>null)}))))
      .filter(item=>item.aircraft?.rows.some(aircraft=>aircraft.configured)).map(item=>item.carrier)
    :result.carriers;
  const administration=await(await carrierAdministrationServices()).access();
  const scheduleWorkflow=work==="schedules";
  return <WorkspaceShell user={result.user}>
    {route&&<Link href="/work" className="back">← Work options</Link>}
    <p className="eyebrow">{label??"YOUR WORKSPACE"}</p>
    <div className="carrier-selection-heading"><div><h1>Select a carrier</h1><p className="muted">Choose the airline you want to work with.</p></div>{administration.canCreate&&work==="ahm"&&<div className="solution-admin-actions"><Link className="button-link" href="/carriers/new">ADD NEW CARRIER</Link></div>}</div>
    <div className="section-heading"><h2>{scheduleWorkflow?"Schedule-ready carriers":"Authorised carriers"}</h2><span className="badge">{carriers.length} available</span></div>
    {carriers.length?<div className="carrier-grid">{carriers.map(carrier=><Link prefetch={false} className="carrier-card" key={carrier.iata} href={`/carrier/${encodeURIComponent(carrier.iata)}/${route??"dashboard"}`}><CarrierLogo iata={carrier.iata} logoUrl={carrier.logoUrl}/><div><h3>{carrier.name}</h3><p>{carrier.iata} · {label?`Open ${label}`:"Open carrier workspace"}</p></div><span className="arrow" aria-hidden="true">↗</span></Link>)}</div>:<section className="empty"><h2>{scheduleWorkflow?"No schedule-ready carriers":"No carriers available"}</h2><p>{scheduleWorkflow?"A carrier must have at least one configured aircraft before its schedules can be created or amended.":"Your account is signed in, but no carriers are available to you. Contact your organisation administrator to request access."}</p></section>}
  </WorkspaceShell>;
}
