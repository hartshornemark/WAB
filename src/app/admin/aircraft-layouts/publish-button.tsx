"use client";
import {useState,useTransition} from "react";
import {publishAircraftLayoutVersion,publishVerifiedAircraftLayouts} from "./actions";
export function PublishButton(){
 const [pending,start]=useTransition(),[result,setResult]=useState<{ok:boolean;message:string}|null>(null);
 return <div><button type="button" disabled={pending} onClick={()=>start(async()=>setResult(await publishVerifiedAircraftLayouts()))}>{pending?"PUBLISHING…":"PUBLISH VERIFIED TEMPLATES"}</button>{result&&<p role="status" className={result.ok?"":"field-error"}>{result.message}</p>}</div>;
}
export function PublishVersionButton({typeCode,subtype,version}:{typeCode:string;subtype:string;version:number}){
 const [pending,start]=useTransition(),[result,setResult]=useState<{ok:boolean;message:string}|null>(null);
 return <div><button type="button" disabled={pending} onClick={()=>start(async()=>setResult(await publishAircraftLayoutVersion(typeCode,subtype,version)))}>{pending?"PUBLISHING…":`PUBLISH ${typeCode}-${subtype} VERSION ${version}`}</button>{result&&<p role="status" className={result.ok?"":"field-error"}>{result.message}</p>}</div>;
}
