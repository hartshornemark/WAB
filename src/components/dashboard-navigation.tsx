"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

function dashboardHref(pathname: string) {
  const parts = pathname.split("/").filter(Boolean).map(decodeURIComponent);
  if (parts[0] !== "carrier" || !parts[1]) return null;
  const iata = encodeURIComponent(parts[1]);
  if (parts[2] === "aircraft" && parts[3] && parts[4]) {
    return `/carrier/${iata}/aircraft/${encodeURIComponent(parts[3])}/${encodeURIComponent(parts[4])}/dashboard`;
  }
  return `/carrier/${iata}/dashboard`;
}

export function DashboardNavigation() {
  const href = dashboardHref(usePathname());
  if (!href) return null;
  return <Link className="topbar-dashboard" href={href}>DASHBOARD</Link>;
}
