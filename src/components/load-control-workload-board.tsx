"use client";

import Link from "next/link";
import { useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { startOperationalFlight } from "@/app/load-control-actions";
import { operationalFlightLabel } from "@/domain/operational-flights";
import type { DailyBoardFlight } from "@/ports/operational-flight-repository";

export type WorkloadFlight = DailyBoardFlight & {carrierIata:string;carrierName:string;serviceDate:string};

export function LoadControlWorkloadBoard({flights}:{flights:WorkloadFlight[]}) {
  const router=useRouter(),[pending,startTransition]=useTransition(),[query,setQuery]=useState(""),[status,setStatus]=useState("ALL"),[notice,setNotice]=useState<{ok:boolean;message:string}|null>(null);
  const visible=useMemo(()=>flights.filter(f=>{
    const needle=query.trim().toUpperCase();
    const match=!needle||`${f.carrierIata} ${f.carrierName} ${f.airlineDesignator}${f.flightNumber}${f.operationalSuffix} ${f.departureAirport} ${f.arrivalAirport} ${f.itinerary.route}`.toUpperCase().includes(needle);
    return match&&(status==="ALL"||f.status===status);
  }),[flights,query,status]);
  const summary={total:flights.length,scheduled:flights.filter(f=>f.status==="SCHEDULED").length,active:flights.filter(f=>!["SCHEDULED","CLOSED","CANCELLED"].includes(f.status)).length,final:flights.filter(f=>f.status==="LOADSHEET_FINAL").length};
  function openScheduled(f:WorkloadFlight){startTransition(async()=>{const result=await startOperationalFlight(f.carrierIata,f.scheduleLegId!,f.serviceDate);if(!result.ok){setNotice(result);return}router.push(`/carrier/${encodeURIComponent(f.carrierIata)}/load-control/${result.operationalFlightId}`)})}
  return <>
    <div className="load-control-summary"><div><span>Total sectors</span><strong>{summary.total}</strong></div><div><span>Awaiting start</span><strong>{summary.scheduled}</strong></div><div><span>Active</span><strong>{summary.active}</strong></div><div><span>Final loadsheet</span><strong>{summary.final}</strong></div></div>
    <section className="load-control-board-card"><div className="load-control-filters"><label>Search<input value={query} onChange={event=>setQuery(event.target.value)} placeholder="Carrier, flight, airport or itinerary"/></label><label>Workflow status<select value={status} onChange={event=>setStatus(event.target.value)}><option value="ALL">All statuses</option><option value="SCHEDULED">Awaiting start</option><option value="INITIATED">Initiated</option><option value="LOAD_PLANNING">Load planning</option><option value="LOADSHEET_PRELIMINARY">Preliminary loadsheet</option><option value="LOADSHEET_FINAL">Final loadsheet</option><option value="CLOSED">Closed</option></select></label></div>
      {notice&&<p className={notice.ok?"load-control-notice success":"load-control-notice error"}>{notice.message}</p>}
      <div className="daily-flight-list">{visible.map(f=><article className="daily-flight-card" key={`${f.carrierIata}-${f.operationalFlightId??f.scheduleLegId}`}><header><div><span className="load-control-carrier">{f.carrierIata}</span><span className="load-control-source">{f.sourceType==="AD_HOC"?"AD-HOC":"SCHEDULED"}</span><strong>{f.airlineDesignator}{f.flightNumber}{f.operationalSuffix}</strong><span>{f.itinerary.route}</span></div><span className={`load-control-status ${f.status.toLowerCase()}`}>{operationalFlightLabel(f.status)}</span></header><div className="daily-flight-sector"><div><small>SECTOR / STD</small><b>{f.departureAirport} → {f.arrivalAirport}</b><span>{new Date(f.departureLocal).toLocaleTimeString([],{hour:"2-digit",minute:"2-digit",hour12:false})} – {new Date(f.arrivalLocal).toLocaleTimeString([],{hour:"2-digit",minute:"2-digit",hour12:false})}</span></div><div><small>AIRCRAFT</small><b>{f.aircraftType}{f.aircraftSubtype?`-${f.aircraftSubtype}`:""}</b><span>{f.aircraftRegistration??"Registration not assigned"}</span></div><div><small>OPERATING CODES</small><b>Crew {f.crewCode??"—"} · Pantry {f.pantryCode??"—"}</b><span>{f.passengerWeightBasis?`Passenger ${f.passengerWeightBasis}`:"Passenger N/A"} · {f.baggageWeightBasis?`Baggage ${f.baggageWeightBasis}`:"Baggage N/A"}</span></div><div className="daily-flight-action">{f.operationalFlightId?<Link className="button-link" href={`/carrier/${encodeURIComponent(f.carrierIata)}/load-control/${f.operationalFlightId}`}>OPEN FLIGHT</Link>:<button disabled={pending||!f.canStart} onClick={()=>openScheduled(f)}>{f.ready?"START FLIGHT":"CONFIGURE SCHEDULE"}</button>}</div></div>{!f.ready&&<p className="daily-flight-warning">Complete this segment’s Load Control defaults in Flight Schedules before starting it.</p>}</article>)}{!visible.length&&<p className="load-control-empty">No sectors match this workload view.</p>}</div>
    </section>
  </>;
}
