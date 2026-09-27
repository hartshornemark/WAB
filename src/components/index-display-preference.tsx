"use client";

import {createContext,useContext,useEffect,useMemo,useState,type ReactNode} from "react";
import {usePathname} from "next/navigation";
import type {IndexDecimalPlaces} from "@/domain/display-standards";

type PreferenceEvent={iata:string;indexDecimalPlaces:IndexDecimalPlaces};
const IndexDisplayPreferenceContext=createContext<IndexDecimalPlaces>(1);
export const INDEX_DISPLAY_PREFERENCE_EVENT="carrier-index-display-preference";

export function IndexDisplayPreferenceProvider({children}:{children:ReactNode}){
  const pathname=usePathname();
  const iata=useMemo(()=>{const match=pathname.match(/^\/carrier\/([^/]+)/);return match?decodeURIComponent(match[1]):null},[pathname]);
  const[places,setPlaces]=useState<IndexDecimalPlaces>(1);
  useEffect(()=>{
    queueMicrotask(()=>setPlaces(1));
    if(!iata)return;
    const controller=new AbortController();
    fetch(`/api/carrier/${encodeURIComponent(iata)}/display-preferences`,{cache:"no-store",signal:controller.signal})
      .then(response=>response.ok?response.json():null)
      .then(value=>{if(value?.indexDecimalPlaces===2)setPlaces(2);else if(value?.indexDecimalPlaces===1)setPlaces(1)})
      .catch(()=>{});
    const update=(event:Event)=>{const detail=(event as CustomEvent<PreferenceEvent>).detail;if(detail?.iata===iata)setPlaces(detail.indexDecimalPlaces)};
    window.addEventListener(INDEX_DISPLAY_PREFERENCE_EVENT,update);
    return()=>{controller.abort();window.removeEventListener(INDEX_DISPLAY_PREFERENCE_EVENT,update)};
  },[iata]);
  return <IndexDisplayPreferenceContext.Provider value={places}>{children}</IndexDisplayPreferenceContext.Provider>;
}

export function useIndexDecimalPlaces(){return useContext(IndexDisplayPreferenceContext)}
