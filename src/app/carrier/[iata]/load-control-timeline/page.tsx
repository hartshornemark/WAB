import Link from"next/link";
import{notFound,redirect}from"next/navigation";
import{operationalTimelineServices}from"@/composition/services";
import{AuthenticationRequired,CarrierUnavailable}from"@/domain/models";
import{WorkspaceShell}from"@/components/workspace-shell";
import{OperationalTimelineConfigurationPanel}from"@/components/operational-timeline-configuration";
export default async function OperationalTimelinePage({params}:{params:Promise<{iata:string}>}){const{iata}=await params;const result=await(await operationalTimelineServices()).get(iata).catch(error=>{if(error instanceof AuthenticationRequired)redirect("/login");if(error instanceof CarrierUnavailable)notFound();throw error});return <WorkspaceShell user={result.user}><Link href={`/carrier/${encodeURIComponent(iata)}/dashboard`} className="back">← Carrier Home</Link><p className="eyebrow">LOAD CONTROL CONFIGURATION / {result.carrier.iata}</p><div className="load-control-heading"><div><h1>Load Control Timeline</h1><p className="dashboard-intro">Set the carrier’s operational deadlines relative to scheduled departure, then add aircraft-type variations only where they are needed.</p></div></div><OperationalTimelineConfigurationPanel iata={iata} initial={result.timeline}/></WorkspaceShell>}
