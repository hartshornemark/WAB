"use client";

import {createContext,useCallback,useContext,useEffect,useId,useRef,useState,useTransition,type ComponentProps,type ReactNode} from "react";
import {createSaveFeedback,initialSaveFeedback,type SaveFeedbackSnapshot} from "@/domain/save-feedback";

type Feedback = ReturnType<typeof createSaveFeedback> & {snapshot:SaveFeedbackSnapshot;pending:boolean};
const Context = createContext<Feedback|null>(null);

/** Preserve each editor's existing success/close work until its receipt is exited. */
export function useSaveFeedback() {
  const [snapshot,setSnapshot] = useState(initialSaveFeedback);
  const [controller] = useState(() => createSaveFeedback(setSnapshot));
  const [transitionPending,startTransition] = useTransition();
  const pending = snapshot.busy || transitionPending;
  const start = useCallback((action:()=>void|Promise<void>) => startTransition(() => controller.run(action)),[controller]);
  const complete=useCallback((action:()=>void)=>controller.complete(()=>{
    for(let index=localStorage.length-1;index>=0;index--){const key=localStorage.key(index);if(key?.startsWith("dashboard-summary"))localStorage.removeItem(key)}
    action();
  }),[controller]);
  return [pending,start,{...controller,complete,snapshot,pending}] as const;
}

export function SaveScope({feedback,children}:{feedback:Feedback;children:ReactNode}) {
  return <Context.Provider value={feedback}>{children}{feedback.snapshot.error&&<p className="field-error" role="alert">{feedback.snapshot.error}</p>}</Context.Provider>;
}

function useLocked() {
  const feedback=useContext(Context);
  return !!feedback&&(feedback.pending||feedback.snapshot.state==="saved");
}

// Native controls retain their attributes, layout and existing disabled rules.
// This also locks controls rendered by the editor's row/field helper components.
export function SaveInput(props:ComponentProps<"input">) {const locked=useLocked(),feedback=useContext(Context);return <input {...props} disabled={props.disabled||locked} onChange={event=>{feedback?.clearSelection();props.onChange?.(event);}}/>;}
export function SaveSelect(props:ComponentProps<"select">) {const locked=useLocked(),feedback=useContext(Context);return <select {...props} disabled={props.disabled||locked} onChange={event=>{feedback?.clearSelection();props.onChange?.(event);}}/>;}
export function SaveTextarea(props:ComponentProps<"textarea">) {const locked=useLocked();return <textarea {...props} disabled={props.disabled||locked}/>;}
export function SaveButton(props:ComponentProps<"button">) {const locked=useLocked(),feedback=useContext(Context);return <button {...props} disabled={props.disabled||locked} onClick={event=>{feedback?.clearSelection();props.onClick?.(event);}}/>;}
export function SaveCancel(props:ComponentProps<"button">) {
  const feedback=useContext(Context);
  if(feedback?.snapshot.state==="saved")return null;
  return <SaveButton {...props} className={`${props.className??""} save-cancel`}>CANCEL</SaveButton>;
}

export function SaveSubmit({onClick,className,...props}:ComponentProps<"button">) {
  const feedback=useContext(Context),id=useId(),exit=useRef<HTMLButtonElement>(null);
  const active=feedback?.snapshot.activeId===id;
  const state=active?(feedback.snapshot.state==="saved"?"saved":feedback.pending?"saving":"editing"):"editing";
  const locked=!!feedback&&(feedback.pending||feedback.snapshot.state==="saved");
  useEffect(()=>{if(state==="saved"&&!feedback?.pending)exit.current?.focus();},[state,feedback?.pending]);
  return <span className="save-actions save-actions-inline" aria-busy={state==="saving"}>
    <button {...props} className={`${className??""} save-action save-action--${state}`} disabled={props.disabled||locked} onClick={event=>{
      if(feedback&&!feedback.select(id)){event.preventDefault();return;}
      onClick?.(event);
    }}>
      {state==="saving"&&<span className="save-spinner" aria-hidden="true"/>}
      {state==="saving"?"SAVING…":state==="saved"?"SAVED":"SAVE"}
    </button>
    {state==="saved"&&<button ref={exit} type="button" className="secondary save-exit" disabled={feedback?.pending} onClick={()=>feedback?.exit()}>EXIT</button>}
    <span className="sr-only" role="status" aria-live="polite" aria-atomic="true">{state==="saving"?"Saving changes.":state==="saved"?"Changes saved successfully.":""}</span>
  </span>;
}
