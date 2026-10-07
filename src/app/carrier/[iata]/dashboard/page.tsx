import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { carrierHomeServices } from "@/composition/services";
import { AuthenticationRequired, CarrierUnavailable } from "@/domain/models";
import { WorkspaceShell } from "@/components/workspace-shell";
import { CarrierLogo } from "@/components/carrier-logo";
import { DashboardAircraftStatus,DashboardAircraftStatusProvider } from "@/components/dashboard-aircraft-status";

const aircraftProfilesByType:Record<string,string>={
  "310":"/aircraft-profiles/a310-300.png?v=1",
  "313":"/aircraft-profiles/a310-300.png?v=1",
  "319":"/aircraft-profiles/a319-100.png?v=3",
  "320":"/aircraft-profiles/a320-200.png?v=3",
  "321":"/aircraft-profiles/a321-passenger.png?v=1",
  "33F":"/aircraft-profiles/a330-200f.png?v=1",
  "359":"/aircraft-profiles/a359-900.png?v=1",
  "DH3":"/aircraft-profiles/dh3-300.png?v=3",
  "738":"/aircraft-profiles/738-800.png?v=2",
  "763":"/aircraft-profiles/b767-300.png?v=1",
  "7M9":"/aircraft-profiles/7m9-900.png?v=2",
  "SSC":"/aircraft-profiles/concorde.png?v=1",
};

const aircraftProfilesByTypeAndSubtype:Record<string,string>={
  "321:P2F":"/aircraft-profiles/a321-p2f.png?v=1",
};

export default async function CarrierDashboardPage({params}:{params:Promise<{iata:string}>}) {
  const {iata}=await params;
  const result=await (await carrierHomeServices()).get(iata).catch(error=>{
    if(error instanceof AuthenticationRequired) redirect("/login");
    if(error instanceof CarrierUnavailable) notFound();
    throw error;
  });
  const aircraft=result.aircraft;
  const carrierBase=`/carrier/${encodeURIComponent(iata)}`;
  if(aircraft.rows.length===0){
    const query=new URLSearchParams({mode:"carrier",iata:result.carrier.iata,carrier:result.carrier.name,...(result.carrier.logoUrl?{logo:result.carrier.logoUrl}:{})});
    redirect(`/mockups/configuration-dashboard.html?${query.toString()}`);
  }
  return <WorkspaceShell user={result.user}>
    <Link href="/carriers" className="back">← Change carrier</Link>
    <p className="eyebrow">CARRIER WORKSPACE / {result.carrier.iata}</p>
    <div className="crew-carrier-heading"><CarrierLogo iata={iata} logoUrl={result.carrier.logoUrl}/><div><h1>Carrier Home</h1><p className="muted">{result.carrier.name}</p></div></div>
    <>
      <div className="dashboard-home-actions">
        <Link className="button-link" href={`${carrierBase}/loadsheet-simulator`}>OPEN EDP LOADSHEET SIMULATOR</Link>
        <Link className="button-link secondary" href={`${carrierBase}/flight-schedules`}>FLIGHT SCHEDULES</Link>
        <Link className="button-link secondary" href={`${carrierBase}/aircraft`}>ADD OR CHANGE AIRCRAFT</Link>
      </div>
      <p className="dashboard-intro">Select an aircraft to open its complete configuration dashboard.</p>
      <DashboardAircraftStatusProvider iata={iata} aircraft={aircraft.rows}><div className="dashboard-aircraft-grid">{aircraft.rows.map(row=>{
        const href=`${carrierBase}/aircraft/${encodeURIComponent(row.typeCode)}/${encodeURIComponent(row.subtype)}/dashboard`;
        const typeCode=row.typeCode.trim().toUpperCase();
        const subtype=row.subtype.trim().toUpperCase();
        const profile=aircraftProfilesByTypeAndSubtype[`${typeCode}:${subtype}`]??aircraftProfilesByType[typeCode];
        return <Link className="dashboard-aircraft-card" href={href} prefetch={false} key={`${row.typeCode}-${row.subtype}`}>
          <span className="dashboard-aircraft-top"><span className="dashboard-aircraft-code">{row.typeCode}-{row.subtype}</span><span className="dashboard-aircraft-open"><DashboardAircraftStatus typeCode={row.typeCode} subtype={row.subtype}/><span className="dashboard-open">OPEN DASHBOARD →</span></span></span>
          <span className={`dashboard-aircraft-body${profile?" has-profile":""}`}><span className="dashboard-aircraft-copy"><h2>{row.identityName||row.aircraftName}</h2><span className="dashboard-aircraft-maker">{row.manufacturerName}</span></span>{profile&&<img className="dashboard-aircraft-profile" src={profile} alt={`${row.identityName||row.aircraftName} side profile`}/>}</span>
        </Link>;
      })}</div></DashboardAircraftStatusProvider>
    </>
  </WorkspaceShell>;
}
