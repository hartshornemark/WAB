import Image from "next/image";
import Link from "next/link";
import type { AuthenticatedUser } from "@/domain/models";
import { signOut } from "@/app/actions";
import { DashboardNavigation } from "@/components/dashboard-navigation";
import { IndexDisplayPreferenceProvider } from "@/components/index-display-preference";
export function WorkspaceShell({ user, children }: { user: AuthenticatedUser; children: React.ReactNode }) {
  return <IndexDisplayPreferenceProvider><header className="topbar"><Link href="/carriers" className="brand"><Image src="/brand/wb-logo.png" alt="W/B" width={384} height={633} className="workspace-logo" preload unoptimized /> CARRIER CONFIGURATION</Link><div className="account"><DashboardNavigation/><span>{user.displayName || user.email || "Signed in"}</span><form action={signOut}><button className="secondary">Sign out</button></form></div></header><main className="workspace">{children}</main><footer className="workspace-footer">CARRIER CONFIGURATION <span>Operations workspace</span></footer></IndexDisplayPreferenceProvider>;
}
