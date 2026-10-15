"use client";

import { usePathname, useSearchParams } from "next/navigation";
import { workstreamLabel } from "@/domain/workstream";

export function WorkstreamLabel() {
  const pathname = usePathname();
  const searchParams = useSearchParams();
  return <>{workstreamLabel(pathname, searchParams.get("work"))}</>;
}
