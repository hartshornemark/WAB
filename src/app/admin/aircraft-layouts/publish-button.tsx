"use client";
import {useState,useTransition} from "react";
import {publishVerifiedAircraftLayouts} from "./actions";
export function PublishButton(){
 const [pending,start]=useTransition(),[result,setResult]=useState<{ok:boolean;message:string}|null>(null);
 return <div><button type="button" disabled={pending} onClick={()=>start(async()=>setResult(await publishVerifiedAircraftLayouts()))}>{pending?"PUBLISHING…":"PUBLISH VERIFIED TEMPLATES"}</button>{result&&<p role="status" className={result.ok?"":"field-error"}>{result.message}</p>}</div>;
}
