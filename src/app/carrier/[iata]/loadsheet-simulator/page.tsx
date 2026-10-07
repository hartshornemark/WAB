import Link from "next/link";
import {notFound,redirect} from "next/navigation";
import {CarrierLogo} from "@/components/carrier-logo";
import {WorkspaceShell} from "@/components/workspace-shell";
import {carrierHomeServices} from "@/composition/services";
import {AuthenticationRequired,CarrierUnavailable} from "@/domain/models";

export default async function LoadsheetSimulatorAircraftSelection({params}:{params:Promise<{iata:string}>}){
 const{iata}=await params;
 const result=await(await carrierHomeServices()).get(iata).catch(error=>{
  if(error instanceof AuthenticationRequired)redirect("/login");
  if(error instanceof CarrierUnavailable)notFound();
  throw error;
 });
 const carrierBase=`/carrier/${encodeURIComponent(iata)}`;
 return <WorkspaceShell user={result.user}>
  <Link href={`${carrierBase}/dashboard`} className="back">← Carrier Home</Link>
  <p className="eyebrow">DATA VERIFICATION / {result.carrier.iata}</p>
  <div className="crew-carrier-heading"><CarrierLogo iata={iata} logoUrl={result.carrier.logoUrl}/><div><h1>EDP Loadsheet Simulator</h1><p className="muted">{result.carrier.name}</p></div></div>
  <section className="sim-card simulator-aircraft-selection">
   <h2>Select an aircraft type</h2>
   <p>The simulator will apply the registrations, DOW/DOI, loading positions, fuel schedules, structural limits and balance data saved for the selected aircraft.</p>
   {result.aircraft.rows.length?<div className="aircraft-list">{result.aircraft.rows.map(row=><Link className="aircraft-card" key={`${row.typeCode}-${row.subtype}`} href={`${carrierBase}/aircraft/${encodeURIComponent(row.typeCode)}/${encodeURIComponent(row.subtype)}/loadsheet-simulator`}><span className="aircraft-code">{row.typeCode}</span><div><strong>{row.identityName||row.aircraftName}</strong><p>{row.typeCode}-{row.subtype}{row.manufacturerName?` · ${row.manufacturerName}`:""}</p></div><span className="simulator-select-action">SELECT →</span></Link>)}</div>:<div className="sim-prompt">No aircraft types have been added for this carrier. Complete C1 before running the simulator.</div>}
  </section>
 </WorkspaceShell>;
}
