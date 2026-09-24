import Link from "next/link";
import {notFound,redirect} from "next/navigation";
import {aircraftC1Services,services} from "@/composition/services";
import {AuthenticationRequired,CarrierUnavailable} from "@/domain/models";
import {WorkspaceShell} from "@/components/workspace-shell";
import {CarrierLogo} from "@/components/carrier-logo";
import {SectionHeader} from "@/components/section-header";
import {ConfigurationStatusBadge} from "@/components/configuration-status-badge";

export default async function CarrierA5Page({params}:{params:Promise<{iata:string}>}){
 const{iata}=await params;
 const result=await(await services()).selectCarrier(iata).catch(error=>{if(error instanceof AuthenticationRequired)redirect("/login");if(error instanceof CarrierUnavailable)notFound();throw error});
 const aircraft=await(await aircraftC1Services()).list(iata);
 if(aircraft.rows.length===1){const row=aircraft.rows[0];redirect(`/carrier/${encodeURIComponent(iata)}/aircraft/${encodeURIComponent(row.typeCode)}/${encodeURIComponent(row.subtype)}/c2?sheet=A5#automatic-documents`);}
 return <WorkspaceShell user={result.user}>
  <Link href="/carriers" className="back">← Change carrier</Link>
  <p className="eyebrow">CARRIER WORKSPACE / {result.carrier.iata} / SECTION A</p>
  <div className="crew-carrier-heading"><CarrierLogo iata={iata} logoUrl={result.carrier.logoUrl}/><h1>{result.carrier.name}</h1></div>
  <section className="overview"><SectionHeader id="a5-title" title="A5. AUTOMATIC DOCUMENTS" reference="(AHM565 Sheet A5)"><ConfigurationStatusBadge status="incomplete" variant="large"/></SectionHeader>
   {aircraft.rows.length===0?<><h3>Aircraft setup is required</h3><p>Automatic Document requirements belong to an aircraft configuration. Add the first aircraft on C1, then return to A5.</p><Link className="button-link" href={`/carrier/${encodeURIComponent(iata)}/aircraft`}>OPEN C1 AIRCRAFT SETUP</Link></>:<><p>Select the aircraft whose Automatic Document requirements you want to configure.</p><div className="aircraft-list">{aircraft.rows.map(row=><Link className="aircraft-card" key={`${row.typeCode}-${row.subtype}`} href={`/carrier/${encodeURIComponent(iata)}/aircraft/${encodeURIComponent(row.typeCode)}/${encodeURIComponent(row.subtype)}/c2?sheet=A5#automatic-documents`}><strong>{row.identityName||row.aircraftName}</strong><span>{row.typeCode}-{row.subtype}</span></Link>)}</div></>}
  </section>
  <nav className="section-navigation" aria-label="Carrier setup sections"><Link className="section-link secondary" href={`/carrier/${encodeURIComponent(iata)}`}>← A2. CARRIERS’ CONTACTS</Link><Link className="section-link" href={`/carrier/${encodeURIComponent(iata)}?sheet=B1`}>NEXT: B1. UNITS &amp; CODES →</Link></nav>
 </WorkspaceShell>;
}
