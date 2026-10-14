"use client";
import{useEffect,useState}from"react";
import{operationalFlightTiming,type OperationalFlightStatus}from"@/domain/operational-flights";
import{operationalTimelineHealth,type OperationalTimelineCompletion,type OperationalTimelineConfiguration}from"@/domain/operational-timeline";

export function OperationalFlightStatusBadges({status,departureLocal,departureUtcOffsetMinutes,delayMinutes,configuration,completion,initialNow}:{status:OperationalFlightStatus;departureLocal:string;departureUtcOffsetMinutes:number|null;delayMinutes:number;configuration:OperationalTimelineConfiguration;completion:OperationalTimelineCompletion;initialNow:string}){
  const[now,setNow]=useState(()=>Date.parse(initialNow));
  useEffect(()=>{const timer=window.setInterval(()=>setNow(Date.now()),60_000);return()=>window.clearInterval(timer)},[]);
  const moment=new Date(now),timing=operationalFlightTiming(departureLocal,departureUtcOffsetMinutes,status,moment,delayMinutes),workflow=operationalTimelineHealth({departureLocal,departureUtcOffsetMinutes,delayMinutes,configuration,completion,cancelled:status==="CANCELLED",now:moment});
  return <div className="operational-flight-statuses" aria-label="Flight status">
    <span className={`operational-flight-status-badge workflow ${workflow.tone}`} title={workflow.description}><small>PROCESS · {workflow.target}</small><strong>{workflow.label}</strong></span>
    <span className={`operational-flight-status-badge timing ${workflow.tone==="archived"?"archived":timing.tone}`}><small>{delayMinutes?"REVISED DEPARTURE":"TIMING"}</small><strong>{workflow.tone==="archived"?"ARCHIVED":timing.label}</strong></span>
  </div>
}
