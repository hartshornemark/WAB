"use client";

import {Children,isValidElement,type ReactNode,useEffect,useMemo,useRef,useState} from "react";

export type OperationalWorkflowStep={id:string;number:string;label:string;description:string;complete:boolean};

export function OperationalFlightWorkflow({steps,header,children}:{steps:OperationalWorkflowStep[];header:ReactNode;children:ReactNode}){
 const currentIndex=steps.findIndex(step=>!step.complete),resolvedCurrent=currentIndex<0?steps.length-1:currentIndex;
 const defaultStage=steps[resolvedCurrent]?.id??steps[0]?.id??"";
 const validIds=useMemo(()=>new Set(steps.map(step=>step.id)),[steps]);
 const [activeStage,setActiveStage]=useState(defaultStage);
 const shellRef=useRef<HTMLDivElement>(null);
 useEffect(()=>{const sync=()=>{const id=window.location.hash.slice(1);if(validIds.has(id))setActiveStage(id)};sync();window.addEventListener("hashchange",sync);return()=>window.removeEventListener("hashchange",sync)},[validIds]);
 useEffect(()=>{const shell=shellRef.current;if(!shell)return;for(const stage of shell.querySelectorAll<HTMLElement>(`[data-workflow-stage="${activeStage}"]`)){if(stage instanceof HTMLDetailsElement&&stage.classList.contains("operational-collapsible"))stage.open=stage.dataset.workflowOpen==="true";for(const details of stage.querySelectorAll<HTMLDetailsElement>("details.operational-collapsible"))details.open=false}},[activeStage]);
 const select=(id:string)=>{setActiveStage(id);window.history.replaceState(null,"",`${window.location.pathname}${window.location.search}#${id}`)};
 return <div ref={shellRef} className="operational-workflow-shell" data-active-stage={activeStage}>
  <section className="operational-flight-overview">
   {header}
   <nav className="operational-workflow" aria-label="Load Control workflow">
    <ol>{steps.map((step,index)=>{const state=step.complete?"complete":index===resolvedCurrent?"current":"waiting",selected=step.id===activeStage;return <li className={`${state}${selected?" selected":""}`} key={step.id}><button type="button" aria-current={selected?"step":undefined} onClick={()=>select(step.id)}><b>{step.complete?"✓":step.number}</b><span><strong>{step.label}</strong><small>{step.description}</small></span><em>{step.complete?"Complete":index===resolvedCurrent?"Current":"Waiting"}</em></button></li>})}</ol>
   </nav>
  </section>
  <div className="operational-workflow-content">{Children.map(children,child=>isValidElement(child)?child:null)}</div>
 </div>;
}
