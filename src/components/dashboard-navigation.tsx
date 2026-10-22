"use client";

import { useCallback, useEffect, useSyncExternalStore } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { workstreamNavigation } from "@/domain/workstream-navigation";

const dashboardStorageEvent="wab:dashboard-storage";
const noDashboard=()=>null;

export function DashboardNavigation() {
  const pathname=usePathname(),hrefs=workstreamNavigation(pathname);
  const iata=pathname.split("/").filter(Boolean)[1];
  const storageKey=iata?`wab:ahm-dashboard:${decodeURIComponent(iata).toUpperCase()}`:null;
  const subscribe=useCallback((listener:()=>void)=>{
    window.addEventListener("storage",listener);
    window.addEventListener(dashboardStorageEvent,listener);
    return()=>{window.removeEventListener("storage",listener);window.removeEventListener(dashboardStorageEvent,listener)};
  },[]);
  const readDashboard=useCallback(()=>storageKey?localStorage.getItem(storageKey):null,[storageKey]);
  const rememberedDashboard=useSyncExternalStore(subscribe,readDashboard,noDashboard);
  const aircraftDashboard=hrefs?.aircraftDashboard;
  useEffect(()=>{
    if(!storageKey||!aircraftDashboard||localStorage.getItem(storageKey)===aircraftDashboard)return;
    localStorage.setItem(storageKey,aircraftDashboard);
    window.dispatchEvent(new Event(dashboardStorageEvent));
  },[aircraftDashboard,storageKey]);
  if (!hrefs) return null;
  const dashboard=hrefs.aircraftDashboard??rememberedDashboard;
  return <nav className="topbar-workspace-navigation" aria-label="Workspace navigation"><Link className="topbar-work-options" href={hrefs.workOptions}>WORK OPTIONS</Link>{hrefs.carrierHome&&<Link className="topbar-carrier-home" href={hrefs.carrierHome}>CARRIER HOME</Link>}{dashboard&&<Link className="topbar-dashboard" href={dashboard}>DASHBOARD</Link>}</nav>;
}
