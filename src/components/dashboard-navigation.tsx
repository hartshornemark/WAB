"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

function navigationHrefs(pathname: string) {
  const parts = pathname.split("/").filter(Boolean).map(decodeURIComponent);
  if (parts[0] !== "carrier" || !parts[1]) return null;
  const iata = encodeURIComponent(parts[1]);
  const carrierHome = `/carrier/${iata}/dashboard`;
  if (parts[2] === "aircraft" && parts[3] && parts[4]) {
    return {carrierHome,aircraftDashboard:`/carrier/${iata}/aircraft/${encodeURIComponent(parts[3])}/${encodeURIComponent(parts[4])}/dashboard`};
  }
  return {carrierHome,aircraftDashboard:null};
}

export function DashboardNavigation() {
  const hrefs = navigationHrefs(usePathname());
  if (!hrefs) return null;
  return <nav className="topbar-workspace-navigation" aria-label="Workspace navigation"><Link className="topbar-carrier-home" href={hrefs.carrierHome}>CARRIER HOME</Link>{hrefs.aircraftDashboard&&<Link className="topbar-dashboard" href={hrefs.aircraftDashboard}>AIRCRAFT DASHBOARD</Link>}</nav>;
}
