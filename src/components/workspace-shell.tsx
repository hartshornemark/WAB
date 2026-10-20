import Image from "next/image";
import Link from "next/link";
import type { AuthenticatedUser } from "@/domain/models";
import { signOut } from "@/app/actions";
import { DashboardNavigation } from "@/components/dashboard-navigation";
import { IndexDisplayPreferenceProvider } from "@/components/index-display-preference";
import { AddEntryFocus } from "@/components/add-entry-focus";
import { WorkstreamLabel } from "@/components/workstream-label";
import { Suspense } from "react";
export function WorkspaceShell({ user, children }: { user: AuthenticatedUser; children: React.ReactNode }) {
  return <IndexDisplayPreferenceProvider><AddEntryFocus/><header className="topbar"><Link href="/work" className="brand"><Image src="/brand/wb-logo.png" alt="W/B" width={384} height={633} className="workspace-logo" preload unoptimized /> <Suspense fallback="OPERATIONS WORKSPACE"><WorkstreamLabel/></Suspense></Link><div className="account"><DashboardNavigation/><span>{user.displayName || user.email || "Signed in"}</span><form action={signOut}><button className="secondary">Sign out</button></form></div></header>{user.readOnly&&<div className="read-only-banner" role="status"><strong>READ ONLY ACCESS</strong><span>You can view this workspace, but changes cannot be made using this account.</span></div>}<main className={`workspace${user.readOnly?" read-only-workspace":""}`}>{children}</main><footer className="workspace-footer"><Suspense fallback="OPERATIONS WORKSPACE"><WorkstreamLabel/></Suspense> <span>Operations workspace</span></footer></IndexDisplayPreferenceProvider>;
}
