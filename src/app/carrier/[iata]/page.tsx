import {DensitySettings} from "@/components/density-settings";
import { ClassEditor } from "@/components/class-editor";
import { CommodityEditor } from "@/components/commodity-editor";
import { CarrierDetails } from "@/components/carrier-details";
import Link from "next/link";
import { redirect, notFound } from "next/navigation";
import { LogoManager } from "@/components/logo-manager";
import { services, logoServices, detailsServices, commodityServices, classServices, densityServices, aircraftC1Services } from "@/composition/services";
import { AuthenticationRequired, CarrierUnavailable } from "@/domain/models";
import { WorkspaceShell } from "@/components/workspace-shell";
import {b1Statuses} from "@/domain/b1-status";
import {carrierCarriesPassengers} from "@/domain/aircraft-c1";
export default async function CarrierPage({ params, searchParams }: { params: Promise<{ iata: string }>; searchParams: Promise<{ sheet?: string;created?:string;logo?:string }> }) {
  const { iata } = await params;
  const query=await searchParams;const initialStep = query.sheet === "B1" ? "general" : "contact";
  const result = await (await services()).selectCarrier(iata).catch(error => {
    if (error instanceof AuthenticationRequired) redirect("/login");
    if (error instanceof CarrierUnavailable) notFound();
    throw error;
  });
  const canManageLogo = await (await logoServices()).canManage(iata);
  const [details,commodities,densities,classes,aircraft] = await Promise.all([(await detailsServices()).get(iata),(await commodityServices()).get(iata),(await densityServices()).get(iata),(await classServices()).get(iata),(await aircraftC1Services()).list(iata)]);
  const passengerOperations=carrierCarriesPassengers(aircraft.rows);
  const completion=b1Statuses(details,densities,classes,commodities,passengerOperations);
  return <WorkspaceShell user={result.user}><Link href="/carriers" className="back">← Change carrier</Link><p className="eyebrow">CARRIER WORKSPACE / {result.carrier.iata}</p><h1>{result.carrier.name}</h1><p className="muted">Your active carrier is {result.carrier.iata}.</p>{query.created==="1"&&<section className="carrier-created-banner"><div><span className="zero-status">0% CONFIGURED</span><h2>Carrier created</h2><p>The workspace is empty and ready for configuration. Complete A2 below, then continue to A5.</p>{query.logo==="retry"&&<p className="field-error">The carrier was created, but the logo could not be saved. You can upload it again under Carrier identity.</p>}</div><Link className="button-link" href={`/carrier/${encodeURIComponent(iata)}/a5`}>CONTINUE TO A5</Link></section>}<section className="overview carrier-identity"><div className="identity-copy"><span className="badge">Carrier selected</span><h2>Carrier identity</h2><p>These details are maintained centrally by your Solution Administrator.</p><dl><div><dt>IATA code</dt><dd>{result.carrier.iata}</dd></div><div><dt>Carrier name</dt><dd>{result.carrier.name}</dd></div><div><dt>ICAO code</dt><dd>{result.carrier.icao}</dd></div></dl></div><LogoManager iata={iata} logoUrl={result.carrier.logoUrl} canManage={canManageLogo} /></section><CarrierDetails key={`${iata}-${initialStep}`} initialStep={initialStep} iata={iata} initial={details} pageStatus={completion.page} commodityEditor={<><DensitySettings iata={iata} initial={densities}/><ClassEditor iata={iata} initial={classes} passengerOperations={passengerOperations} /><CommodityEditor iata={iata} initial={commodities} /></>} /></WorkspaceShell>;
}
