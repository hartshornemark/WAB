"use client";
import{useEffect,useMemo,useState,useTransition}from"react";
import{proposeOperationalAutoload,type AutoloadActionState}from"@/app/load-control-actions";

const empty:AutoloadActionState={ok:false,message:"",problem:null,solution:null,warnings:[]};

export function LoadPlanningWorkspace({iata,flightId,released,acceptedWeight}:{iata:string;flightId:string;released:boolean;acceptedWeight:number}){
 const[pending,start]=useTransition(),[result,setResult]=useState(empty),[payload,setPayload]=useState({released,acceptedWeight});
 useEffect(()=>{const update=(event:Event)=>{const detail=(event as CustomEvent<{flightId:string;released:boolean;acceptedWeight:number}>).detail;if(detail?.flightId===flightId){setPayload({released:detail.released,acceptedWeight:detail.acceptedWeight});setResult(empty)}};window.addEventListener("wab:freight-acceptance",update);return()=>window.removeEventListener("wab:freight-acceptance",update)},[flightId]);
 const rows=useMemo(()=>{if(!result.problem||!result.solution)return[];const loads=new Map(result.problem.loads.map(load=>[load.id,load])),positions=new Map(result.problem.positions.map(position=>[position.id,position]));return result.solution.assignments.map(assignment=>({assignment,load:loads.get(assignment.loadId),position:positions.get(assignment.positionId)})).filter(row=>row.load&&row.position).sort((a,b)=>(a.load!.unloadOrder-b.load!.unloadOrder)||a.position!.description.localeCompare(b.position!.description))},[result]);
 const run=()=>start(async()=>setResult(await proposeOperationalAutoload(iata,flightId)));
 const status=result.solution?.status??(payload.released?"READY":"AWAITING PAYLOAD");
 return <details className="load-planning-workspace operational-collapsible" open>
  <summary className="operational-collapsible-summary load-planning-heading">
   <div><p className="eyebrow">LOAD PLANNING</p><h2>AUTOLOAD proposal</h2><p>Place released ULD and Bulk loads using unloading sequence, loading simplicity and Ideal Trim priorities.</p></div>
   <div className="operational-summary-facts">
    <span><small>RELEASED LOAD</small><strong>{Math.round(payload.acceptedWeight).toLocaleString()} KG</strong></span>
    <span><small>ASSIGNMENTS</small><strong>{rows.length||"—"}</strong></span>
    <span className={`summary-emphasis ${result.ok?"ready":"incomplete"}`}><small>SOLVER STATUS</small><strong>{status}</strong></span>
   </div>
  </summary>
  <div className="operational-collapsible-body">
   <div className="load-planning-intro"><div><strong>Proposed loading only</strong><span>The independent validator checks position compatibility, limits, locks and overlapping ULD footprints before the proposal is displayed.</span></div><button type="button" onClick={run} disabled={!payload.released||pending}>{pending?"CALCULATING…":"AUTOLOAD"}</button></div>
   {!payload.released&&<p className="load-control-notice error">Save and release the ULD/Bulk Load Weight Statement before running AUTOLOAD.</p>}
   {result.message&&<p className={`load-control-notice ${result.ok?"success":"error"}`}>{result.message}</p>}
   {result.warnings.map(warning=><p className="load-control-notice warning" key={warning}>{warning}</p>)}
   {result.solution&&<div className="autoload-metrics"><span><small>ENGINE</small><strong>{result.solution.engine}</strong></span><span><small>SOLVE TIME</small><strong>{result.solution.solveMilliseconds.toLocaleString()} ms</strong></span><span><small>UNLOAD PENALTY</small><strong>{result.solution.sequencePenalty??"—"}</strong></span><span><small>IDEAL TRIM DEVIATION</small><strong>{result.solution.trimDeviationScaled===null?"Not scored":(result.solution.trimDeviationScaled/100_000).toFixed(2)}</strong></span></div>}
   {rows.length>0&&<div className="autoload-table"><div className="autoload-row head"><span>Load</span><span>Unload</span><span>Gross</span><span>Proposed position</span><span>Priority</span></div>{rows.map(({assignment,load,position})=><div className="autoload-row" key={assignment.loadId}><span data-label="Load"><strong>{load!.description.split(" · ")[0]}</strong><small>{load!.loadType}{load!.uldCode?` · ${load!.uldCode}`:""}</small></span><span data-label="Unload"><strong>{load!.description.split("unload ")[1]??"—"}</strong></span><span data-label="Gross"><strong>{load!.weightKg.toLocaleString()} KG</strong></span><span data-label="Proposed position"><strong>{position!.description}</strong></span><span data-label="Priority"><strong>{load!.unloadOrder+1}</strong></span></div>)}</div>}
   {result.solution?.messages.map(item=><p className="autoload-note" key={item}>{item}</p>)}
   <p className="autoload-scope"><strong>Current proposal scope:</strong> payload placement, position limits, ULD fit, physical overlap, offload order, simplicity and Ideal Trim. Ground-stability sequence validation must be added before a proposal can be committed as a loading instruction.</p>
  </div>
 </details>
}
