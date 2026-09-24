import Link from"next/link";
import{redirect}from"next/navigation";
import{carrierAdministrationServices}from"@/composition/services";
import{AuthenticationRequired}from"@/domain/models";
import{WorkspaceShell}from"@/components/workspace-shell";
import{NewCarrierForm}from"@/components/new-carrier-form";
export default async function NewCarrierPage(){const access=await(await carrierAdministrationServices()).access().catch(error=>{if(error instanceof AuthenticationRequired)redirect("/login");throw error});return <WorkspaceShell user={access.user}><Link href="/carriers" className="back">← Carrier selection</Link><p className="eyebrow">SOLUTION ADMINISTRATION</p><h1>Create a new carrier</h1><p className="muted new-carrier-intro">Create the carrier identity used throughout the solution. The new carrier starts with no aircraft and no completed configuration pages.</p>{access.canCreate?<section className="overview new-carrier-card"><div className="new-carrier-heading"><div><span className="badge">INITIAL SETUP</span><h2>Carrier identity</h2></div><span className="zero-status">0% CONFIGURED</span></div><NewCarrierForm/></section>:<section className="empty"><h2>Solution Administrator access required</h2><p>Your account cannot create master carrier records.</p></section>}</WorkspaceShell>}
