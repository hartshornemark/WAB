"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { workstreamNavigation } from "@/domain/workstream-navigation";

export function DashboardNavigation() {
  const hrefs = workstreamNavigation(usePathname());
  if (!hrefs) return null;
  return <nav className="topbar-workspace-navigation" aria-label="Workspace navigation"><Link className="topbar-work-options" href={hrefs.workOptions}>WORK OPTIONS</Link>{hrefs.carrierHome&&<Link className="topbar-carrier-home" href={hrefs.carrierHome}>CARRIER HOME</Link>}{hrefs.aircraftDashboard&&<Link className="topbar-dashboard" href={hrefs.aircraftDashboard}>AIRCRAFT DASHBOARD</Link>}</nav>;
}
