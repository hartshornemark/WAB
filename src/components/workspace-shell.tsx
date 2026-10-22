import Image from "next/image";
import Link from "next/link";
import type { AuthenticatedUser } from "@/domain/models";
import { signOut } from "@/app/actions";
import { DashboardNavigation } from "@/components/dashboard-navigation";
import { IndexDisplayPreferenceProvider } from "@/components/index-display-preference";
import { AddEntryFocus } from "@/components/add-entry-focus";
import { WorkstreamLabel } from "@/components/workstream-label";
import { Suspense } from "react";
import { listUserAttention } from "@/app/user-attention-actions";
import { confirmProvisionalUldFromInbox } from "@/app/uld-actions";
export async function WorkspaceShell({ user, children }: { user: AuthenticatedUser; children: React.ReactNode }) {
  const attention=await listUserAttention().catch(()=>[]);
  return <IndexDisplayPreferenceProvider><AddEntryFocus/><header className="topbar"><Link href="/work" className="brand"><Image src="/brand/wb-logo.png" alt="W/B" width={384} height={633} className="workspace-logo" preload unoptimized /> <Suspense fallback="OPERATIONS WORKSPACE"><WorkstreamLabel/></Suspense></Link><div className="account"><DashboardNavigation/>{attention.length>0&&<details className="attention-inbox"><summary aria-label={`${attention.length} attention items`}>ALERTS <strong>{attention.length}</strong></summary><div><header><strong>ATTENTION REQUIRED</strong><span>{attention.length} OPEN</span></header>{attention.map(item=><article key={item.id}><Link href={`/carrier/${encodeURIComponent(item.carrierIata)}/aircraft/${encodeURIComponent(item.aircraftType)}/${encodeURIComponent(item.aircraftSubtype)}/uld-specifications`}><strong>{item.title}</strong><span>{item.carrierIata} · {item.detail}</span><small>{new Date(item.createdAt).toLocaleString()}</small></Link><form action={confirmProvisionalUldFromInbox}><input type="hidden" name="iata" value={item.carrierIata}/><input type="hidden" name="typeCode" value={item.aircraftType}/><input type="hidden" name="subtype" value={item.aircraftSubtype}/><input type="hidden" name="uldCode" value={item.code}/><button type="submit">CONFIRM &amp; ADD TO B5</button></form></article>)}</div></details>}<span>{user.displayName || user.email || "Signed in"}</span><form action={signOut}><button className="secondary">Sign out</button></form></div></header>{user.readOnly&&<div className="read-only-banner" role="status"><strong>READ ONLY ACCESS</strong><span>You can view this workspace, but changes cannot be made using this account.</span></div>}<main className={`workspace${user.readOnly?" read-only-workspace":""}`}>{children}</main><footer className="workspace-footer"><Suspense fallback="OPERATIONS WORKSPACE"><WorkstreamLabel/></Suspense> <span>Operations workspace</span></footer></IndexDisplayPreferenceProvider>;
}
