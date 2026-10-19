"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { workstreamNavigation } from "@/domain/workstream-navigation";

export function DashboardNavigation() {
  const hrefs = workstreamNavigation(usePathname());
  if (!hrefs) return null;
  const dashboard=hrefs.aircraftDashboard??hrefs.carrierHome;
  return <nav className="topbar-workspace-navigation" aria-label="Workspace navigation"><Link className="topbar-work-options" href={hrefs.workOptions}>WORK OPTIONS</Link>{dashboard&&<Link className="topbar-dashboard" href={dashboard}>DASHBOARD</Link>}</nav>;
}
