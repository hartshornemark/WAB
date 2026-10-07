import Link from"next/link";
import{redirect}from"next/navigation";
import{WorkspaceShell}from"@/components/workspace-shell";
import{MasterAirportEditor}from"@/components/master-airport-editor";
import{masterAirportServices}from"@/composition/services";
import{AuthenticationRequired}from"@/domain/models";
export default async function AirportConfigurationPage(){
 const result=await(await masterAirportServices()).get().catch(error=>{if(error instanceof AuthenticationRequired)redirect("/login");throw error});
 return <WorkspaceShell user={result.user}><Link href="/carriers" className="back">← Carrier selection</Link><p className="eyebrow">SOLUTION ADMINISTRATION</p><h1>Airport Configuration</h1><p className="muted airport-admin-intro">Maintain the airport identities and IANA time zones used by flight schedules and Load Control.</p>{"denied" in result?<section className="empty"><h2>Solution Administrator access required</h2><p>Your account cannot maintain the master airport table.</p></section>:<MasterAirportEditor initial={result.airports} timeZones={result.timeZones}/>}</WorkspaceShell>;
}
