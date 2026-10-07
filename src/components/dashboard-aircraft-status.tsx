"use client";

import {createContext,useContext,useEffect,useMemo,useState,type ReactNode} from "react";
import type{DashboardSummaryStatus} from "@/domain/dashboard-summary";

type DisplayStatus=DashboardSummaryStatus|"loading"|"refreshing"|"unavailable";
type AircraftStatus={status:DisplayStatus;attention:string[]};
const labels:Record<DisplayStatus,string>={
  configured:"CONFIGURED",
  partial:"PARTIALLY CONFIGURED",
  incomplete:"INCOMPLETE",
  loading:"LOADING STATUS",
  refreshing:"UPDATING STATUS",
  unavailable:"STATUS UNAVAILABLE",
};

const DashboardStatusesContext=createContext<Record<string,AircraftStatus>|null>(null);
const aircraftKey=(typeCode:string,subtype:string)=>`${typeCode.trim().toUpperCase()}:${subtype.trim().toUpperCase()}`;

export function DashboardAircraftStatusProvider({iata,aircraft,children}:{iata:string;aircraft:Array<{typeCode:string;subtype:string}>;children:ReactNode}){
  const initial=useMemo(()=>Object.fromEntries(aircraft.map(row=>[aircraftKey(row.typeCode,row.subtype),{status:"loading" as const,attention:[]}])) as Record<string,AircraftStatus>,[aircraft]);
  const[resultState,setResultState]=useState({scope:initial,values:initial});
  const statuses=resultState.scope===initial?resultState.values:initial;
  useEffect(()=>{
    const controller=new AbortController();
    const timers:number[]=[];
    const setStatuses=(values:Record<string,AircraftStatus>)=>setResultState({scope:initial,values});
    const unavailable=()=>Object.fromEntries(Object.keys(initial).map(key=>[key,{status:"unavailable" as const,attention:[]}])) as Record<string,AircraftStatus>;
    async function load(attempt=0):Promise<void>{
      try{
        const query=new URLSearchParams();
        aircraft.forEach(row=>query.append("aircraft",aircraftKey(row.typeCode,row.subtype)));
        const response=await fetch(`/api/carrier/${encodeURIComponent(iata)}/aircraft-dashboard-statuses?${query}`,{cache:"no-store",credentials:"same-origin",signal:controller.signal});
        if(!response.ok)throw new Error("Status unavailable");
        const result=await response.json() as {statuses?:Record<string,{status:DashboardSummaryStatus|"unavailable";attention:string[]}>;refreshing?:string[]};
        const refreshing=new Set(result.refreshing??[]);
        setStatuses(Object.fromEntries(Object.keys(initial).map(key=>[key,refreshing.has(key)?{status:"refreshing",attention:[]}:result.statuses?.[key]??{status:"unavailable",attention:[]}])));
        if(refreshing.size&&attempt<5)timers.push(window.setTimeout(()=>void load(attempt+1),2_000));
      }catch(error){if((error as Error).name!=="AbortError")setStatuses(unavailable())}
    }
    void load();
    return()=>{timers.forEach(timer=>window.clearTimeout(timer));controller.abort();};
  },[iata,aircraft,initial]);
  return <DashboardStatusesContext.Provider value={statuses}>{children}</DashboardStatusesContext.Provider>;
}

export function DashboardAircraftStatus({typeCode,subtype}:{typeCode:string;subtype:string}){
  const statuses=useContext(DashboardStatusesContext);
  const result=statuses?.[aircraftKey(typeCode,subtype)]??{status:"loading" as const,attention:[]};
  const label=labels[result.status];
  const detail=result.attention.length?`${label} — review ${result.attention.join(", ")}`:label;
  return <span className={`dashboard-aircraft-status ${result.status}`} role="status" aria-label={`Dashboard status: ${detail}`} title={detail}>
    <span className="dashboard-aircraft-status-dot" aria-hidden="true"/>
    <span>{label}</span>
  </span>;
}
