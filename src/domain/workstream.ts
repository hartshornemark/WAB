const WORKSTREAM_LABELS: Record<string, string> = {
  schedules: "SCHEDULE CREATION / AMENDMENT",
  "load-control": "LOAD CONTROL",
  ahm: "AHM560 / 565 DATABASE",
};

export function workstreamLabel(pathname: string, selectedWorkstream?: string | null) {
  if (pathname === "/work") return "OPERATIONS WORKSPACE";
  if (pathname.startsWith("/admin/airports")) return "AIRPORT CONFIGURATION";
  if (pathname.includes("/flight-schedules")) return "SCHEDULE CREATION / AMENDMENT";
  if (pathname.includes("/load-control")) return "LOAD CONTROL";
  if (pathname === "/carriers" && selectedWorkstream && WORKSTREAM_LABELS[selectedWorkstream]) {
    return WORKSTREAM_LABELS[selectedWorkstream];
  }
  if (pathname.startsWith("/carrier/") || pathname.startsWith("/carriers")) {
    return "AHM560 / 565 DATABASE";
  }
  return "OPERATIONS WORKSPACE";
}
