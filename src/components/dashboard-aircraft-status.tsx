"use client";

import {useEffect,useState} from "react";
import {dashboardSummaryStatus,type DashboardSummaryStatus} from "@/domain/dashboard-summary";

type DisplayStatus=DashboardSummaryStatus|"loading"|"unavailable";
const labels:Record<DisplayStatus,string>={
  configured:"CONFIGURED",
  partial:"PARTIALLY CONFIGURED",
  incomplete:"INCOMPLETE",
  loading:"LOADING STATUS",
  unavailable:"STATUS UNAVAILABLE",
};

export function DashboardAircraftStatus({iata,typeCode,subtype}:{iata:string;typeCode:string;subtype:string}){
  const[status,setStatus]=useState<DisplayStatus>("loading");
  useEffect(()=>{
    const controller=new AbortController();
    const path=`/api/carrier/${encodeURIComponent(iata)}/aircraft/${encodeURIComponent(typeCode)}/${encodeURIComponent(subtype)}/dashboard-status`;
    const cacheKey=`dashboard-summary:v2:${iata.toUpperCase()}:${typeCode.toUpperCase()}:${subtype.toUpperCase()}`;
    try{
      const cached=JSON.parse(localStorage.getItem(cacheKey)??"null") as{status?:DashboardSummaryStatus;storedAt?:number}|null;
      if(cached?.status&&cached.storedAt&&Date.now()-cached.storedAt<300_000){queueMicrotask(()=>setStatus(cached.status!));return()=>controller.abort()}
    }catch{}
    const refresh=()=>fetch(path,{cache:"no-store",credentials:"same-origin",signal:controller.signal})
      .then(async response=>{if(!response.ok)throw new Error("Status unavailable");return response.json() as Promise<{statuses?:Record<string,string>}>})
      .then(result=>{
        const next=result.statuses?dashboardSummaryStatus(result.statuses):"unavailable";
        setStatus(next);
        if(next!=="unavailable")localStorage.setItem(cacheKey,JSON.stringify({status:next,storedAt:Date.now()}));
      })
      .catch(error=>{if((error as Error).name!=="AbortError")setStatus(current=>current==="loading"?"unavailable":current)});
    const idleWindow=window as Window&{requestIdleCallback?:(callback:()=>void,options?:{timeout:number})=>number;cancelIdleCallback?:(id:number)=>void};
    const idleId=idleWindow.requestIdleCallback?.(refresh,{timeout:750});
    const timer=idleId===undefined?window.setTimeout(refresh,0):undefined;
    return()=>{controller.abort();if(idleId!==undefined)idleWindow.cancelIdleCallback?.(idleId);if(timer!==undefined)window.clearTimeout(timer)};
  },[iata,typeCode,subtype]);
  return <span className={`dashboard-aircraft-status ${status}`} role="status" aria-label={`Dashboard status: ${labels[status]}`} title={labels[status]}>
    <span className="dashboard-aircraft-status-dot" aria-hidden="true"/>
    <span>{labels[status]}</span>
  </span>;
}
