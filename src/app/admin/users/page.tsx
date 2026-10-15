import Link from "next/link";
import { redirect } from "next/navigation";
import { WorkspaceShell } from "@/components/workspace-shell";
import { services } from "@/composition/services";

const capabilities=[
  {title:"User records",description:"Create, amend, suspend and reactivate solution users."},
  {title:"Carrier assignments",description:"Select the carriers whose schedules, configuration and flights a user may access."},
  {title:"Location assignments",description:"Define the stations that contribute flights to each user's Load Control workload."},
  {title:"Permissions",description:"Assign view, operate, configure, publish and administration responsibilities."},
] as const;

export default async function UserAdministrationPage(){
  const user=await(await services()).currentUser();
  if(!user)redirect("/login");
  return <WorkspaceShell user={user}><Link href="/work" className="back">← Work options</Link><p className="eyebrow">SOLUTION ADMINISTRATION</p><h1>User Administration</h1><p className="muted user-admin-intro">This workspace will control who can use the solution and which operational work appears for them.</p><section className="user-admin-placeholder"><div className="user-admin-status"><span className="badge">PLANNED WORKSPACE</span><h2>User access model</h2><p>The workflow is reserved and ready for the user directory, assignment and permission controls.</p></div><div className="user-admin-capabilities">{capabilities.map(item=><article key={item.title}><h3>{item.title}</h3><p>{item.description}</p></article>)}</div></section></WorkspaceShell>;
}
