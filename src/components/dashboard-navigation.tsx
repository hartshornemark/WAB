"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { workstreamNavigation } from "@/domain/workstream-navigation";

export function DashboardNavigation() {
  const pathname=usePathname(),hrefs=workstreamNavigation(pathname),[rememberedDashboard,setRememberedDashboard]=useState<string|null>(null);
  useEffect(()=>{
    if(!hrefs)return;
    const iata=pathname.split("/").filter(Boolean)[1];
    if(!iata)return;
    const key=`wab:ahm-dashboard:${decodeURIComponent(iata).toUpperCase()}`;
    if(hrefs.aircraftDashboard){localStorage.setItem(key,hrefs.aircraftDashboard);setRememberedDashboard(hrefs.aircraftDashboard);return;}
    if(hrefs.carrierHome)setRememberedDashboard(localStorage.getItem(key));
  },[hrefs?.aircraftDashboard,hrefs?.carrierHome,pathname]);
  if (!hrefs) return null;
  const dashboard=hrefs.aircraftDashboard??rememberedDashboard;
  return <nav className="topbar-workspace-navigation" aria-label="Workspace navigation"><Link className="topbar-work-options" href={hrefs.workOptions}>WORK OPTIONS</Link>{hrefs.carrierHome&&<Link className="topbar-carrier-home" href={hrefs.carrierHome}>CARRIER HOME</Link>}{dashboard&&<Link className="topbar-dashboard" href={dashboard}>DASHBOARD</Link>}</nav>;
}
