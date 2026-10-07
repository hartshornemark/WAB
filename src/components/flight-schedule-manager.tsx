"use client";
import Link from"next/link";
import{useActionState,useState,useTransition}from"react";
import{useRouter}from"next/navigation";
import{createScheduleRevision,importSsimSchedule,publishSsimSchedule}from"@/app/flight-schedule-actions";
import{initialScheduleActionState}from"@/domain/flight-schedule-action-state";
import type{FlightScheduleImport}from"@/ports/flight-schedule-repository";

const date=(value:string|null)=>value?new Intl.DateTimeFormat("en-GB",{day:"2-digit",month:"short",year:"numeric"}).format(new Date(`${value}T00:00:00Z`)):"—";
const timestamp=(value:string)=>new Intl.DateTimeFormat("en-GB",{dateStyle:"medium",timeStyle:"short"}).format(new Date(value));

export function FlightScheduleManager({iata,imports}:{iata:string;imports:FlightScheduleImport[]}){
  const[actionState,action,pending]=useActionState(importSsimSchedule.bind(null,iata),initialScheduleActionState);
  const[publishState,setPublishState]=useState(initialScheduleActionState),[publishing,startPublishing]=useTransition(),[revisionState,setRevisionState]=useState(initialScheduleActionState),[creatingRevision,startRevision]=useTransition(),router=useRouter();
  const publish=(importId:string)=>startPublishing(async()=>{const result=await publishSsimSchedule(iata,importId);setPublishState(result);if(result.ok)router.refresh()});
  const revise=(importId:string)=>startRevision(async()=>{const result=await createScheduleRevision(iata,importId);setRevisionState(result);if(result.ok&&result.importId)router.push(`/carrier/${encodeURIComponent(iata)}/flight-schedules?edition=${encodeURIComponent(result.importId)}`)});
  const feedback=revisionState.message?revisionState:publishState.message?publishState:actionState;
  return <div className="flight-schedule-manager">
    <section className="configuration-card schedule-upload-card">
      <div><h2>UPLOAD IATA SSIM CHAPTER 7</h2><p className="muted">Select the carrier&apos;s fixed-width TXT schedule. The carrier code, record lengths, dates, routes, times and equipment are checked before an edition can be published.</p></div>
      <form action={action} className="schedule-upload-form"><input name="scheduleFile" type="file" accept=".txt,text/plain" required/><button type="submit" disabled={pending}>{pending?"VALIDATING…":"UPLOAD & VALIDATE"}</button></form>
      {feedback.message&&<p className={feedback.ok?"save-feedback success":"save-feedback error"} role="status">{feedback.message}</p>}
    </section>
    <section className="configuration-card"><h2>SCHEDULE EDITIONS</h2>
      {imports.length===0?<p className="muted">No schedule edition has been created or uploaded for {iata}.</p>:<div className="schedule-editions">
        {imports.map(item=><article className="schedule-edition" key={item.importId}>
          <div className="schedule-edition-main"><strong>{item.fileName}</strong><span>{item.sourceFormat==="MANUAL"?"Manual entry":"SSIM Chapter 7"} · {date(item.coverageStart)} – {date(item.coverageEnd)}</span><span>{item.legCount.toLocaleString()} flight legs · {item.recordCount.toLocaleString()} source records</span><small>Created {timestamp(item.uploadedAt)}</small></div>
          <div className="schedule-edition-action"><span className={`schedule-status ${item.status.toLowerCase()}`}>{item.status}</span><Link className="button-link secondary" href={`/carrier/${encodeURIComponent(iata)}/flight-schedules?edition=${encodeURIComponent(item.importId)}`}>VIEW / REVIEW</Link>{item.status==="PUBLISHED"&&<button type="button" disabled={creatingRevision} onClick={()=>revise(item.importId)}>{creatingRevision?"CREATING…":"CREATE REVISION"}</button>}{item.status==="VALIDATED"&&<button type="button" disabled={publishing} onClick={()=>publish(item.importId)}>{publishing?"PUBLISHING…":"PUBLISH"}</button>}</div>
        </article>)}
      </div>}
    </section>
  </div>;
}
