import Link from"next/link";
import{notFound,redirect}from"next/navigation";
import{flightScheduleServices}from"@/composition/services";
import{AuthenticationRequired,CarrierUnavailable}from"@/domain/models";
import{WorkspaceShell}from"@/components/workspace-shell";
import{FlightScheduleManager}from"@/components/flight-schedule-manager";
import{ManualScheduleEntry}from"@/components/manual-schedule-entry";
import{PublishedScheduleWorkspace}from"@/components/published-schedule-workspace";
import{ScheduleEditionReview}from"@/components/schedule-edition-review";

export default async function FlightSchedulesPage({params,searchParams}:{params:Promise<{iata:string}>;searchParams:Promise<{edition?:string}>}){
  const{iata}=await params,{edition:editionId}=await searchParams;
  const result=await(await flightScheduleServices()).get(iata).catch(error=>{if(error instanceof AuthenticationRequired)redirect("/login");if(error instanceof CarrierUnavailable)notFound();throw error});
  const selected=editionId&&/^[0-9a-f-]{36}$/i.test(editionId)?await(await flightScheduleServices()).getEdition(iata,editionId).then(value=>value.edition).catch(()=>notFound()):null;
  return <WorkspaceShell user={result.user}><Link href={`/carrier/${encodeURIComponent(iata)}/dashboard`} className="back">← Carrier Home</Link><p className="eyebrow">CARRIER WORKSPACE / {result.carrier.iata}</p><h1>Flight Schedules</h1><p className="dashboard-intro">Upload or enter a schedule, review and maintain its flights, publish the operating edition, then add the defaults needed for Load Control.</p><FlightScheduleManager iata={iata} imports={result.imports}/>{selected&&<ScheduleEditionReview iata={iata} edition={selected} workspace={result.workspace}/>}<ManualScheduleEntry iata={iata} imports={result.imports} workspace={result.workspace}/><PublishedScheduleWorkspace iata={iata} workspace={result.workspace}/></WorkspaceShell>;
}
