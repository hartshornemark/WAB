import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { aircraftC1Services, services } from "@/composition/services";
import { AuthenticationRequired, CarrierUnavailable } from "@/domain/models";
import { WorkspaceShell } from "@/components/workspace-shell";
import { CarrierLogo } from "@/components/carrier-logo";

export default async function CarrierDashboardPage({params}:{params:Promise<{iata:string}>}) {
  const {iata}=await params;
  const result=await (await services()).selectCarrier(iata).catch(error=>{
    if(error instanceof AuthenticationRequired) redirect("/login");
    if(error instanceof CarrierUnavailable) notFound();
    throw error;
  });
  const aircraft=await (await aircraftC1Services()).list(iata);
  const carrierBase=`/carrier/${encodeURIComponent(iata)}`;
  if(aircraft.rows.length===0){
    const query=new URLSearchParams({mode:"carrier",iata:result.carrier.iata,carrier:result.carrier.name,...(result.carrier.logoUrl?{logo:result.carrier.logoUrl}:{})});
    redirect(`/mockups/configuration-dashboard.html?${query.toString()}`);
  }
  return <WorkspaceShell user={result.user}>
    <Link href="/carriers" className="back">← Change carrier</Link>
    <p className="eyebrow">CARRIER WORKSPACE / {result.carrier.iata}</p>
    <div className="crew-carrier-heading"><CarrierLogo iata={iata} logoUrl={result.carrier.logoUrl}/><div><h1>Configuration dashboard</h1><p className="muted">{result.carrier.name}</p></div></div>
    <>
      <p className="dashboard-intro">Select an aircraft to open its complete configuration dashboard.</p>
      <div className="dashboard-aircraft-grid">{aircraft.rows.map(row=>{
        const href=`${carrierBase}/aircraft/${encodeURIComponent(row.typeCode)}/${encodeURIComponent(row.subtype)}/dashboard`;
        return <Link className="dashboard-aircraft-card" href={href} key={`${row.typeCode}-${row.subtype}`}>
          <div><span className="dashboard-aircraft-code">{row.typeCode}-{row.subtype}</span><h2>{row.identityName||row.aircraftName}</h2><p>{row.manufacturerName}</p></div><span className="dashboard-open">OPEN DASHBOARD →</span>
        </Link>;
      })}</div>
      <Link className="button-link dashboard-manage-aircraft" href={`${carrierBase}/aircraft`}>ADD OR CHANGE AIRCRAFT</Link>
    </>
  </WorkspaceShell>;
}
