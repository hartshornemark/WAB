export function workstreamNavigation(pathname: string) {
  const parts = pathname.split("/").filter(Boolean).map(decodeURIComponent);
  const workOptions = "/work";
  if (pathname === "/work") return null;
  if (parts[0] !== "carrier" || !parts[1]) return {workOptions,carrierHome:null,aircraftDashboard:null};
  const iata = encodeURIComponent(parts[1]);
  const carrierHome = `/carrier/${iata}/dashboard`;
  if (parts[2] === "dashboard") return {workOptions,carrierHome:null,aircraftDashboard:null};
  if (parts[2] === "flight-schedules" || parts[2]?.startsWith("load-control")) {
    return {workOptions,carrierHome:null,aircraftDashboard:null};
  }
  if (parts[2] === "aircraft" && parts[3] && parts[4]) {
    return {workOptions,carrierHome:null,aircraftDashboard:`/carrier/${iata}/aircraft/${encodeURIComponent(parts[3])}/${encodeURIComponent(parts[4])}/dashboard`};
  }
  return {workOptions,carrierHome,aircraftDashboard:null};
}
