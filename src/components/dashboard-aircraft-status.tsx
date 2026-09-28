"use client";

import {createContext,useContext,useEffect,useMemo,useState,type ReactNode} from "react";
import type{DashboardSummaryStatus} from "@/domain/dashboard-summary";

type DisplayStatus=DashboardSummaryStatus|"loading"|"unavailable";
type AircraftStatus={status:DisplayStatus;attention:string[]};
const labels:Record<DisplayStatus,string>={
  configured:"CONFIGURED",
  partial:"PARTIALLY CONFIGURED",
  incomplete:"INCOMPLETE",
  loading:"LOADING STATUS",
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
    const setStatuses=(values:Record<string,AircraftStatus>)=>setResultState({scope:initial,values});
    fetch(`/api/carrier/${encodeURIComponent(iata)}/aircraft-dashboard-statuses`,{cache:"no-store",credentials:"same-origin",signal:controller.signal})
      .then(async response=>{if(!response.ok)throw new Error("Status unavailable");return response.json() as Promise<{statuses?:Record<string,{status:DashboardSummaryStatus|"unavailable";attention:string[]}>}>})
      .then(result=>setStatuses(Object.fromEntries(Object.keys(initial).map(key=>[key,result.statuses?.[key]??{status:"unavailable",attention:[]}]))))
      .catch(error=>{if((error as Error).name!=="AbortError")setStatuses(Object.fromEntries(Object.keys(initial).map(key=>[key,{status:"unavailable",attention:[]}])))});
    return()=>controller.abort();
  },[iata,initial]);
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
