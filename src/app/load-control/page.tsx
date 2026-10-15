import Link from "next/link";
import { redirect } from "next/navigation";
import { LoadControlWorkloadBoard, type WorkloadFlight } from "@/components/load-control-workload-board";
import { WorkspaceShell } from "@/components/workspace-shell";
import { operationalFlightServices, services } from "@/composition/services";
import { AuthenticationRequired } from "@/domain/models";
import { sortLoadControlWorkload } from "@/domain/load-control-workload";

function today(){return new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Manila",year:"numeric",month:"2-digit",day:"2-digit"}).format(new Date())}

export default async function LoadControlWorkloadPage({searchParams}:{searchParams:Promise<{date?:string;airport?:string}>}) {
  const query=await searchParams,date=/^\d{4}-\d{2}-\d{2}$/.test(query.date??"")?query.date!:today(),airport=/^[A-Za-z]{3}$/.test(query.airport??"")?query.airport!.toUpperCase():"";
  const access=await(await services()).listCarriers().catch(error=>{if(error instanceof AuthenticationRequired)redirect("/login");throw error});
  const operations=await operationalFlightServices();
  const results=await Promise.allSettled(access.carriers.map(async carrier=>({carrier,board:(await operations.board(carrier.iata,date,airport)).board})));
  const available=results.flatMap(result=>result.status==="fulfilled"?[result.value]:[]);
  const airports=[...new Map(available.flatMap(({board})=>board.airports).map(item=>[item.iata,item])).values()].sort((a,b)=>a.iata.localeCompare(b.iata));
  const flights=sortLoadControlWorkload(
    available.flatMap(({carrier,board})=>board.flights.map(flight=>({
      ...flight,
      carrierIata:carrier.iata,
      carrierName:carrier.name,
      serviceDate:board.serviceDate,
    } as WorkloadFlight))),
  );
  return <WorkspaceShell user={access.user}><Link href="/work" className="back">← Work options</Link><p className="eyebrow">LOAD CONTROL</p><div className="load-control-heading"><div><h1>Operational Workload</h1><p className="dashboard-intro">All flights available to you, across authorised carriers and locations, ordered by scheduled departure time.</p></div><form><label>Date<input type="date" name="date" defaultValue={date}/></label><label>Location<select name="airport" defaultValue={airport}><option value="">All locations</option>{airports.map(item=><option value={item.iata} key={item.iata}>{item.iata} · {item.name}</option>)}</select></label><button type="submit">VIEW WORKLOAD</button></form></div><LoadControlWorkloadBoard flights={flights}/></WorkspaceShell>;
}
